import XCTest
import SwiftData
@testable import Pawtrackr

/// End-to-end: a check-in followed by an actor-processed checkout must propagate the
/// visit into every surface the groomer eventually reads it from — pet/client relationships,
/// the day/service/category aggregates, the audit transaction record, and Payment linkage.
@MainActor
final class CheckoutHistoryIntegrationTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var visitRepo: VisitRepository!
    var actor: CheckoutTransactionActor!
    var client: Client!
    var pet: Pet!
    var bath: Service!
    var nailTrim: Service!

    override func setUpWithError() throws {
        let schema = Schema(PawtrackrSchema.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [config])
        context = container.mainContext

        client = Client(firstName: "Jane", lastName: "Doe", phone: "5551234567")
        context.insert(client)
        pet = Pet(name: "Buddy", species: .dog)
        pet.owner = client
        context.insert(pet)
        bath = Service(name: "Bath", category: .groom, basePrice: Decimal(30))
        nailTrim = Service(name: "Nail Trim", category: .addOn, basePrice: Decimal(15))
        context.insert(bath)
        context.insert(nailTrim)
        try context.save()

        visitRepo = VisitRepository(modelContext: context, eventBus: GlobalEventBus())
        actor = CheckoutTransactionActor(modelContainer: container)
        Formatters.updateCurrencySymbol("$")
    }

    override func tearDownWithError() throws {
        container = nil; context = nil; visitRepo = nil; actor = nil
        client = nil; pet = nil; bath = nil; nailTrim = nil
    }

    func testCheckInThenCheckout_PersistedVisitFetchableByUUID() async throws {
        let visit = try await visitRepo.checkIn(pet: pet, date: .now)
        let result = try await processCheckout(visit: visit, total: Decimal(45))

        // Use a fresh ModelContext to bust the main context's cached (pre-actor) Visit
        // instance. This mirrors what a SwiftUI screen opening after checkout sees via @Query.
        let freshContext = ModelContext(container)
        let visitUUID = visit.uuid
        let refetched = try XCTUnwrap(
            try freshContext.fetch(FetchDescriptor<Visit>(predicate: #Predicate<Visit> { $0.uuid == visitUUID })).first
        )
        XCTAssertEqual(refetched.total, Decimal(string: "45.00"))
        XCTAssertTrue(refetched.isCompleted)
        XCTAssertNotNil(refetched.payment)
        XCTAssertEqual(refetched.persistentModelID, result.visitID)
    }

    func testCheckInThenCheckout_VisitDiscoverableViaClientPetRelationship() async throws {
        let visit = try await visitRepo.checkIn(pet: pet, date: .now)
        _ = try await processCheckout(visit: visit, total: Decimal(45))

        // The Client → Pet → Visit path used by ClientDetailViewModel must surface this visit.
        let visitsViaClient = (client.pets ?? []).flatMap { $0.visits ?? [] }
        XCTAssertTrue(visitsViaClient.contains { $0.uuid == visit.uuid },
            "Completed visit must be reachable through Client.pets[].visits — that's how ClientDetailView shows history.")
    }

    func testCheckInThenCheckout_DaySummaryReflectsRevenueAndCount() async throws {
        let visit = try await visitRepo.checkIn(pet: pet, date: .now)
        let result = try await processCheckout(visit: visit, total: Decimal(45))

        let day = Calendar.current.startOfDay(for: result.endedAt)
        let summaries = try context.fetch(FetchDescriptor<DaySummary>(predicate: #Predicate<DaySummary> { $0.day == day }))
        let aggregate = SummaryUpdater.collapsedDayAggregates(from: summaries)[day]
        XCTAssertEqual(aggregate?.revenue, Decimal(string: "45.00"))
        XCTAssertEqual(aggregate?.visitCount, 1)
    }

    func testCheckInThenCheckout_ServiceDaySummaryHasEachLineItem() async throws {
        let visit = try await visitRepo.checkIn(pet: pet, date: .now)
        let result = try await processCheckout(visit: visit, total: Decimal(45))
        let day = Calendar.current.startOfDay(for: result.endedAt)

        let summaries = try context.fetch(FetchDescriptor<ServiceDaySummary>(predicate: #Predicate<ServiceDaySummary> { $0.day == day }))
        let counts = SummaryUpdater.collapsedServiceCounts(from: summaries)
        XCTAssertEqual(counts["Bath"], 1)
        XCTAssertEqual(counts["Nail Trim"], 1)
    }

    func testCheckInThenCheckout_CategoryDaySummaryReflectsMixedCategories() async throws {
        let visit = try await visitRepo.checkIn(pet: pet, date: .now)
        let result = try await processCheckout(visit: visit, total: Decimal(45))
        let day = Calendar.current.startOfDay(for: result.endedAt)

        let summaries = try context.fetch(FetchDescriptor<CategoryDaySummary>(predicate: #Predicate<CategoryDaySummary> { $0.day == day }))
        let counts = SummaryUpdater.collapsedCategoryCounts(from: summaries)
        XCTAssertEqual(counts["Grooming"], 1)
        XCTAssertEqual(counts["Add-on"], 1)
    }

    func testCheckInThenCheckout_AuditTransactionRecorded() async throws {
        let visit = try await visitRepo.checkIn(pet: pet, date: .now)
        _ = try await processCheckout(visit: visit, total: Decimal(45))

        let transactions = try context.fetch(FetchDescriptor<CheckoutTransaction>())
        let txn = try XCTUnwrap(transactions.first)
        XCTAssertEqual(transactions.count, 1, "Idempotency key should produce exactly one audit row.")
        XCTAssertEqual(txn.status, .succeeded)
        XCTAssertEqual(txn.amount, Decimal(string: "45.00"))
        XCTAssertEqual(txn.idempotencyKey, "checkout:\(visit.uuid.uuidString)")
        XCTAssertEqual(txn.attemptCount, 1)
    }

    func testCheckInThenCheckout_PaymentLinkedWithMethodAndReference() async throws {
        let visit = try await visitRepo.checkIn(pet: pet, date: .now)
        _ = try await processCheckout(visit: visit, total: Decimal(45), method: .creditCard, reference: "1234")

        let freshContext = ModelContext(container)
        let visitUUID = visit.uuid
        let refetched = try XCTUnwrap(
            try freshContext.fetch(FetchDescriptor<Visit>(predicate: #Predicate<Visit> { $0.uuid == visitUUID })).first
        )
        XCTAssertEqual(refetched.payment?.method, .creditCard)
        XCTAssertEqual(refetched.payment?.amount, Decimal(string: "45.00"))
        XCTAssertEqual(refetched.payment?.externalReference, "1234")
    }

    func testCheckInThenCheckout_RetryIsIdempotent() async throws {
        let visit = try await visitRepo.checkIn(pet: pet, date: .now)
        let first = try await processCheckout(visit: visit, total: Decimal(45))
        let second = try await processCheckout(visit: visit, total: Decimal(45))

        XCTAssertEqual(first.endedAt, second.endedAt, "Idempotent retry must return the original completion timestamp.")
        XCTAssertEqual(try context.fetch(FetchDescriptor<CheckoutTransaction>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Payment>()).count, 1, "Second attempt must not create a duplicate Payment.")
    }

    // MARK: - Helper

    private func processCheckout(
        visit: Visit,
        total: Decimal,
        method: Payment.Method = .cash,
        reference: String? = nil
    ) async throws -> CheckoutResult {
        let request = CheckoutRequest(
            visitUUID: visit.uuid,
            petUUID: pet.uuid,
            clientUUID: client.uuid,
            amount: total,
            paymentMethod: method,
            externalReference: reference,
            sessionNotes: nil,
            behaviorTags: [],
            beforePhotoData: nil,
            afterPhotoData: nil,
            selectedServiceIDs: [bath.persistentModelID],
            selectedAddOnIDs: [nailTrim.persistentModelID]
        )
        return try await actor.process(request)
    }
}
