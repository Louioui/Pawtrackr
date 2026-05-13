import XCTest
import SwiftData
@testable import Pawtrackr

/// Direct unit tests for VisitRepository — the check-in / check-out / save / delete surface
/// touched by the dashboard, client-detail, and active-visit screens.
@MainActor
final class VisitRepositoryTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var repository: VisitRepository!
    var client: Client!
    var pet: Pet!

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
        try context.save()

        repository = VisitRepository(modelContainer: container, eventBus: GlobalEventBus())
    }

    override func tearDownWithError() throws {
        container = nil
        context = nil
        repository = nil
        client = nil
        pet = nil
    }

    func testCheckIn_CreatesActiveVisitOnMainContext() async throws {
        let started = Date()
        let visit = try await repository.checkIn(pet: pet, date: started)

        XCTAssertNotNil(visit.modelContext)
        XCTAssertTrue(visit.isActive)
        XCTAssertNil(visit.endedAt)
        XCTAssertEqual(visit.pet?.uuid, pet.uuid)
        XCTAssertEqual(visit.startedAt.timeIntervalSince1970, started.timeIntervalSince1970, accuracy: 0.001)
    }

    func testCheckIn_VisitAppearsInPetVisitsRelationship() async throws {
        _ = try await repository.checkIn(pet: pet, date: .now)
        XCTAssertEqual((pet.visits ?? []).count, 1)
        XCTAssertEqual((pet.visits ?? []).first?.endedAt, nil)
    }

    func testCheckIn_PersistsAndIsFetchable() async throws {
        let created = try await repository.checkIn(pet: pet, date: .now)
        let uuid = created.uuid
        let descriptor = FetchDescriptor<Visit>(predicate: #Predicate<Visit> { $0.uuid == uuid })
        XCTAssertEqual(try context.fetch(descriptor).count, 1)
    }

    func testCheckIn_PostsVisitDidStartNotification() async throws {
        let exp = expectation(forNotification: .visitDidStart, object: nil, handler: nil)
        _ = try await repository.checkIn(pet: pet, date: .now)
        await fulfillment(of: [exp], timeout: 1.0)
    }

    func testCheckOut_SetsEndedAtAndTotal() async throws {
        let visit = try await repository.checkIn(pet: pet, date: .now)
        visit.addItem(title: "Bath", unitPrice: 30.00)
        let endedAt = Date()

        try await repository.checkOut(visit: visit, total: 30.00, now: endedAt)

        XCTAssertNotNil(visit.endedAt)
        XCTAssertTrue(visit.isCompleted)
        XCTAssertEqual(visit.total, Decimal(string: "30.00"))
    }

    func testCheckOut_RebuildsDaySummaryForThatDay() async throws {
        let visit = try await repository.checkIn(pet: pet, date: .now)
        visit.addItem(title: "Bath", unitPrice: 30.00)
        let payment = Payment(amount: 30.00, method: .cash, paidAt: .now)
        context.insert(payment)
        visit.attachPayment(payment)

        try await repository.checkOut(visit: visit, total: 30.00, now: .now)

        let day = Calendar.current.startOfDay(for: try XCTUnwrap(visit.endedAt))
        let summaries = try context.fetch(FetchDescriptor<DaySummary>(predicate: #Predicate<DaySummary> { $0.day == day }))
        let aggregate = SummaryUpdater.collapsedDayAggregates(from: summaries)[day]
        XCTAssertEqual(aggregate?.revenue, Decimal(string: "30.00"))
        XCTAssertEqual(aggregate?.visitCount, 1)
    }

    func testCheckOut_PostsVisitDidCompleteNotification() async throws {
        let visit = try await repository.checkIn(pet: pet, date: .now)
        let exp = expectation(forNotification: .visitDidComplete, object: nil, handler: nil)
        try await repository.checkOut(visit: visit, total: 25.00, now: .now)
        await fulfillment(of: [exp], timeout: 1.0)
    }

    func testSaveVisit_PersistsToStore() async throws {
        // `Visit(pet: pet)` may implicitly join `pet`'s context — that's fine.
        // What we care about is that after `saveVisit`, the row exists in the store.
        let visit = Visit(pet: pet)

        try await repository.saveVisit(visit)

        XCTAssertNotNil(visit.modelContext)
        let uuid = visit.uuid
        let descriptor = FetchDescriptor<Visit>(predicate: #Predicate<Visit> { $0.uuid == uuid })
        XCTAssertEqual(try context.fetch(descriptor).count, 1)
    }

    func testDeleteVisit_RemovesFromStoreAndRebuildsDaySummary() async throws {
        let visit = try await repository.checkIn(pet: pet, date: .now)
        visit.addItem(title: "Bath", unitPrice: 30.00)
        try await repository.checkOut(visit: visit, total: 30.00, now: .now)
        let day = Calendar.current.startOfDay(for: try XCTUnwrap(visit.endedAt))

        try await repository.deleteVisit(visit)

        let visitUUID = visit.uuid
        XCTAssertEqual(try context.fetch(FetchDescriptor<Visit>(predicate: #Predicate<Visit> { $0.uuid == visitUUID })).count, 0)

        let summaries = try context.fetch(FetchDescriptor<DaySummary>(predicate: #Predicate<DaySummary> { $0.day == day }))
        let aggregate = SummaryUpdater.collapsedDayAggregates(from: summaries)[day]
        XCTAssertEqual(aggregate?.revenue ?? .zero, .zero)
        XCTAssertEqual(aggregate?.visitCount ?? 0, 0)
    }

    func testFetchVisits_RespectsPredicateAndLimit() async throws {
        for _ in 0..<5 {
            _ = try await repository.checkIn(pet: pet, date: .now)
        }
        let petUUID = pet.uuid
        let predicate = #Predicate<Visit> { $0.pet?.uuid == petUUID }
        let result = try await repository.fetchVisits(predicate: predicate, sortBy: [], limit: 3)
        XCTAssertEqual(result.count, 3)
    }

    func testCheckInFromAppointment_LinksAppointmentAndMarksCheckedIn() async throws {
        let appointment = Appointment(date: .now, pet: pet, user: nil)
        context.insert(appointment)
        try context.save()

        let visit = try await repository.checkIn(from: appointment)

        XCTAssertEqual(visit.appointment?.uuid, appointment.uuid)
        XCTAssertEqual(appointment.status, .checkedIn)
        XCTAssertEqual(appointment.visit?.uuid, visit.uuid)
    }
}
