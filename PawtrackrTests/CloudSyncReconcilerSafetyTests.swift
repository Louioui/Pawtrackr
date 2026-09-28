import XCTest
import SwiftData
@testable import Pawtrackr

/// The post-import reconciler must never destroy customer history.
///
/// It used to merge clients and pets that share a UUID by deleting one twin,
/// and the cascade took that twin's pets, visits and payments with it on every
/// device. A fix was written up in June but never landed; these tests pin it.
@MainActor
final class CloudSyncReconcilerSafetyTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema(PawtrackrSchema.models)
        // Local-only: a signed-in test simulator must not upload test data.
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [config])
        context = container.mainContext
    }

    override func tearDownWithError() throws {
        context = nil
        container = nil
    }

    func testDuplicateClientsKeepEveryPetVisitAndPayment() throws {
        let original = try makeClient("Ava", petName: "Milo", paid: 80)
        let twin = try makeClient("Ava", petName: "Luna", paid: 65)
        twin.uuid = original.uuid
        twin.updatedAt = original.updatedAt.addingTimeInterval(60)
        try context.save()

        let report = CloudSyncReconciler.reconcileImportedData(in: context)

        XCTAssertEqual(report.duplicateClientGroups, 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Client>()), 2, "Twins are reported, not deleted.")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Pet>()), 2)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Visit>()), 2)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Payment>()), 2)
        XCTAssertEqual(Set(try context.fetch(FetchDescriptor<Client>()).map(\.firstName)), ["Ava"])
    }

    func testDuplicatePetsKeepTheirVisits() throws {
        let client = try makeClient("Jordan", petName: "Rex", paid: 50)
        let twinPet = Pet(name: "Rex", species: .dog)
        context.insert(twinPet)
        client.addPet(twinPet)
        twinPet.uuid = try XCTUnwrap(client.pets?.first { $0 !== twinPet }).uuid
        let twinVisit = Visit(pet: twinPet, startedAt: .now.addingTimeInterval(-7_200))
        context.insert(twinVisit)
        twinVisit.endedAt = .now.addingTimeInterval(-3_600)
        try context.save()

        let report = CloudSyncReconciler.reconcileImportedData(in: context)

        XCTAssertEqual(report.duplicatePetGroups, 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Pet>()), 2)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Visit>()), 2)
    }

    func testDuplicateActiveVisitsMergeWithoutLosingItemsOrThePayment() throws {
        let pet = Pet(name: "Milo", species: .dog)
        context.insert(pet)
        let startedAt = Date.now.addingTimeInterval(-600)

        // Two devices checked the same pet in at the same time.
        let canonical = Visit(pet: pet, startedAt: startedAt)
        context.insert(canonical)
        canonical.createdAt = startedAt
        let bath = VisitItem(name: "Bath", unitPrice: 30, visit: canonical)
        context.insert(bath)
        canonical.addItem(bath)

        let duplicate = Visit(pet: pet, startedAt: startedAt.addingTimeInterval(20))
        context.insert(duplicate)
        duplicate.createdAt = startedAt.addingTimeInterval(20)
        duplicate.sessionToken = canonical.sessionToken
        let sameBath = VisitItem(name: "Bath", unitPrice: 30, visit: duplicate)
        let nails = VisitItem(name: "Nail Trim", unitPrice: 15, visit: duplicate)
        context.insert(sameBath)
        context.insert(nails)
        duplicate.addItem(sameBath)
        duplicate.addItem(nails)
        let payment = Payment(amount: 45, method: .cash)
        context.insert(payment)
        duplicate.attachPayment(payment)
        try context.save()

        let report = CloudSyncReconciler.reconcileImportedData(in: context)

        XCTAssertEqual(report.duplicateVisitsRemoved, 1)
        let visits = try context.fetch(FetchDescriptor<Visit>())
        XCTAssertEqual(visits.count, 1)
        let survivor = try XCTUnwrap(visits.first)
        XCTAssertEqual(Set((survivor.items ?? []).map(\.name)), ["Bath", "Nail Trim"], "The duplicate's unique item moved over.")
        XCTAssertEqual(survivor.payment?.amount, 45, "The payment moved over instead of being cascade-deleted.")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Payment>()), 1)
        XCTAssertEqual(report.orphanVisitItemCount, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<VisitItem>()).filter { $0.visit == nil }.count, 0)
    }

    // MARK: - Helpers

    /// A client with one pet and one completed, paid visit.
    private func makeClient(_ firstName: String, petName: String, paid amount: Decimal) throws -> Client {
        let client = Client(firstName: firstName, lastName: "Martinez")
        context.insert(client)
        let pet = Pet(name: petName, species: .dog)
        context.insert(pet)
        client.addPet(pet)
        let visit = Visit(pet: pet, startedAt: .now.addingTimeInterval(-86_400))
        context.insert(visit)
        visit.endedAt = .now.addingTimeInterval(-82_800)
        let payment = Payment(amount: amount, method: .cash)
        context.insert(payment)
        visit.attachPayment(payment)
        try context.save()
        return client
    }
}
