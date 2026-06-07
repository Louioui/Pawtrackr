import XCTest
import SwiftData
import CloudKit
@testable import Pawtrackr

@MainActor
final class CloudKitSafetyRegressionTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema(PawtrackrSchema.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [config])
        context = container.mainContext
    }

    override func tearDownWithError() throws {
        UserDefaults.standard.removeObject(forKey: "lastSummarySyncDate")
        UserDefaults.standard.removeObject(forKey: "lastSummaryRebuildDate")
        OfflineMutationBuffer.clear()
        container = nil
        context = nil
    }

    func testBehaviorTagsRoundTripThroughJsonBackingStore() throws {
        let client = Client(firstName: "Ava", lastName: "Stone")
        let pet = Pet(name: "Milo", species: .dog)
        pet.owner = client
        pet.setBehaviorTags(["Nervous", "Senior"])

        let visit = Visit(pet: pet)
        visit.behaviorTags = ["Nervous", "Matting"]

        context.insert(client)
        context.insert(pet)
        context.insert(visit)
        try context.save()

        XCTAssertEqual(pet.behaviorTags, ["Nervous", "Senior"])
        XCTAssertEqual(visit.behaviorTags, ["Nervous", "Matting"])
        XCTAssertTrue(pet.behaviorTagsRaw.contains("Nervous"))
        XCTAssertTrue(visit.behaviorTagsRaw.contains("Matting"))
    }

    func testDefaultPhotoPrunerDoesNotDeleteSyncedVisitPhotos() throws {
        let oldDate = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -365, to: .now))
        let pet = Pet(name: "Luna", species: .dog)
        let visit = Visit(pet: pet, startedAt: oldDate)
        visit.beforePhotoData = Data([0x01, 0x02, 0x03])
        visit.afterPhotoData = Data([0x04, 0x05, 0x06])

        context.insert(pet)
        context.insert(visit)
        try context.save()

        DataPruner.pruneOldPhotos(olderThan: 180, in: context)

        XCTAssertEqual(visit.beforePhotoData, Data([0x01, 0x02, 0x03]))
        XCTAssertEqual(visit.afterPhotoData, Data([0x04, 0x05, 0x06]))
    }

    func testFullSummaryRebuildIgnoresStaleIncrementalWatermark() throws {
        let oldDate = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -45, to: .now))
        let day = Calendar.current.startOfDay(for: oldDate)
        let pet = Pet(name: "Buddy", species: .dog)
        let visit = Visit(pet: pet, startedAt: oldDate)
        visit.markCheckedOut(total: Decimal(string: "72.50")!, now: oldDate.addingTimeInterval(1800))

        UserDefaults.standard.set(Date(), forKey: "lastSummarySyncDate")

        context.insert(pet)
        context.insert(visit)
        try context.save()

        SummaryUpdater.rebuildAllSummaries(in: context)

        let summaries = try context.fetch(FetchDescriptor<DaySummary>())
        let summary = try XCTUnwrap(summaries.first { $0.day == day })
        XCTAssertEqual(summary.revenue, Decimal(string: "72.50")!)
        XCTAssertEqual(summary.visitCount, 1)
    }

    func testFullSummaryRebuildCreatesClientInsightCache() throws {
        let client = Client(firstName: "Rae", lastName: "Miller")
        let pet = Pet(name: "Piper", species: .dog)
        pet.owner = client
        context.insert(client)
        context.insert(pet)

        let firstVisit = Visit(pet: pet, startedAt: .now.addingTimeInterval(-14 * 24 * 3600))
        firstVisit.markCheckedOut(total: 45, now: .now.addingTimeInterval(-14 * 24 * 3600 + 1800))
        let secondVisit = Visit(pet: pet, startedAt: .now.addingTimeInterval(-3600))
        secondVisit.markCheckedOut(total: 55, now: .now)
        context.insert(firstVisit)
        context.insert(secondVisit)
        try context.save()

        SummaryUpdater.rebuildAllSummaries(in: context)

        let rows = try context.fetch(FetchDescriptor<ClientInsightSummary>())
        let row = try XCTUnwrap(rows.first { $0.clientUUID == client.uuid })
        XCTAssertEqual(row.clientName, "Rae Miller")
        XCTAssertEqual(row.totalSpent, Decimal(100))
        XCTAssertEqual(row.visitCount, 2)
        XCTAssertTrue(row.isRecurring)
    }

    func testVisitAndPaymentRecordConflictDiagnostics() throws {
        let pet = Pet(name: "Scout", species: .dog)
        let visit = Visit(pet: pet)
        let payment = Payment(amount: 10, method: .cash)
        visit.attachPayment(payment)

        context.insert(pet)
        context.insert(visit)
        context.insert(payment)
        try context.save()

        XCTAssertEqual(visit.lastModifiedBy, DeviceIdentity.currentID)
        XCTAssertEqual(payment.lastModifiedBy, DeviceIdentity.currentID)
        XCTAssertFalse(visit.lastModifiedAt > Date())
        XCTAssertFalse(payment.lastModifiedAt > Date())
    }

    func testCloudImportReconcilerMergesDuplicateActiveVisitSession() throws {
        let pet = Pet(name: "Scout", species: .dog)
        let started = Date()
        let first = Visit(pet: pet, startedAt: started)
        first.setNote("Checked in at front desk")
        first.behaviorTags = ["Matting"]

        let duplicate = Visit(pet: pet, startedAt: started.addingTimeInterval(30))
        duplicate.sessionToken = first.sessionToken
        duplicate.setNote("Groomer added oatmeal shampoo note")
        duplicate.behaviorTags = ["Sensitive"]

        context.insert(pet)
        context.insert(first)
        context.insert(duplicate)
        try context.save()

        _ = CloudSyncReconciler.reconcileImportedData(in: context)

        let active = try context.fetch(FetchDescriptor<Visit>(predicate: #Predicate { $0.endedAt == nil }))
            .filter { $0.pet?.uuid == pet.uuid }
        XCTAssertEqual(active.count, 1)
        let merged = try XCTUnwrap(active.first)
        XCTAssertTrue(merged.note?.contains("front desk") == true)
        XCTAssertTrue(merged.note?.contains("oatmeal shampoo") == true)
        XCTAssertEqual(Set(merged.behaviorTags), Set(["Matting", "Sensitive"]))
    }

    func testOfflineMutationBufferCapsFlushBatchAtFortyRecords() throws {
        OfflineMutationBuffer.clear()
        for index in 0..<45 {
            OfflineMutationBuffer.append(
                operation: "offline edit \(index)",
                entityName: "Visit",
                changedKeys: ["note", "note", "updatedAt"]
            )
        }

        let batch = OfflineMutationBuffer.peekBatch()
        XCTAssertEqual(batch.count, 40)
        XCTAssertEqual(batch.first?.changedKeys, ["note", "updatedAt"])
        XCTAssertEqual(OfflineMutationBuffer.count, 45)
    }

    func testCloudKitQuotaClassifierFindsNestedPartialFailure() throws {
        let partial = CKError(
            .partialFailure,
            userInfo: [
                CKPartialErrorsByItemIDKey: [
                    "record-1": CKError(.quotaExceeded)
                ]
            ]
        )

        let wrapped = NSError(
            domain: NSCocoaErrorDomain,
            code: 134417,
            userInfo: [NSUnderlyingErrorKey: partial]
        )

        XCTAssertTrue(CloudKitMonitor.isQuotaExceededError(wrapped))
    }

    func testCloudKitQuotaClassifierFindsDaemonQuotaText() throws {
        let daemonStyleError = NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.partialFailure.rawValue,
            userInfo: [
                NSLocalizedDescriptionKey: "Received error 47 (quotaExceeded) from the server"
            ]
        )

        XCTAssertTrue(CloudKitMonitor.isQuotaExceededError(daemonStyleError))
    }

    func testPetHistoryUsesCheckoutCompletionDateForMonthScope() async throws {
        let calendar = Calendar.current
        let monthStart = try XCTUnwrap(calendar.date(from: calendar.dateComponents([.year, .month], from: .now)))
        let startedPreviousMonth = monthStart.addingTimeInterval(-30 * 60)
        let endedThisMonth = monthStart.addingTimeInterval(30 * 60)

        let pet = Pet(name: "Mocha", species: .dog)
        let visit = Visit(pet: pet, startedAt: startedPreviousMonth)
        visit.addItem(title: "Bath", unitPrice: 45, quantity: 1)
        visit.markCheckedOut(total: 45, now: endedThisMonth)
        let payment = Payment(amount: 45, method: .cash, paidAt: endedThisMonth)
        visit.attachPayment(payment)

        context.insert(pet)
        context.insert(visit)
        context.insert(payment)
        try context.save()

        let vm = PetHistoryViewModel(pet: pet, modelContext: context)
        await vm.refresh()

        XCTAssertEqual(vm.filtered.count, 1)
        XCTAssertEqual(vm.filtered.first?.uuid, visit.uuid)
    }

    func testPetHistorySearchFiltersDisplayedRowsAndExports() async throws {
        let pet = Pet(name: "Nori", species: .dog)
        let visit = Visit(pet: pet, startedAt: .now.addingTimeInterval(-3600))
        visit.addItem(title: "De-shedding", unitPrice: 35, quantity: 1)
        visit.note = "Sensitive paws"
        visit.markCheckedOut(total: 35, now: .now)
        let payment = Payment(amount: 35, method: .zelle, externalReference: "REF-123")
        visit.attachPayment(payment)

        context.insert(pet)
        context.insert(visit)
        context.insert(payment)
        try context.save()

        let vm = PetHistoryViewModel(pet: pet, modelContext: context)
        await vm.refresh()

        vm.searchText = "de-shed"
        XCTAssertEqual(vm.filtered.count, 1)
        XCTAssertTrue(String(decoding: vm.exportCSV(), as: UTF8.self).contains("De-shedding"))

        vm.searchText = "no-match"
        XCTAssertTrue(vm.filtered.isEmpty)
    }
}
