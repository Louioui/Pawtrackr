import XCTest
import SwiftData
@testable import Pawtrackr

/// Coverage for ClientDetailViewModel — paging, range filtering, observer-driven refresh,
/// and the check-in/check-out/add-service actions powering the per-client detail screen.
@MainActor
final class ClientDetailViewModelTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
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

        Formatters.updateCurrencySymbol("$")
    }

    override func tearDownWithError() throws {
        container = nil; context = nil; client = nil; pet = nil
    }

    func testInit_PopulatesPetsFromClient() async {
        let vm = ClientDetailViewModel(client: client, modelContext: context)
        XCTAssertEqual(vm.pets.count, 1)
        XCTAssertEqual(vm.pets.first?.uuid, pet.uuid)
    }

    func testRefreshRecentVisits_ReturnsCompletedVisitsForClient() async throws {
        seedCompletedVisit(at: .now, total: 30)
        seedCompletedVisit(at: .now, total: 45)

        let vm = ClientDetailViewModel(client: client, modelContext: context)
        await waitForFetch(vm)

        XCTAssertEqual(vm.recentVisits.count, 2)
        XCTAssertEqual(vm.visitCount, 2)
        XCTAssertEqual(vm.grandRevenue, Decimal(string: "75.00"))
    }

    func testRefreshRecentVisits_ExcludesUnfinishedVisits() async throws {
        // Active (no endedAt) — must not appear in recentVisits.
        let active = Visit(pet: pet)
        context.insert(active)
        try context.save()

        let vm = ClientDetailViewModel(client: client, modelContext: context)
        await waitForFetch(vm)

        XCTAssertEqual(vm.recentVisits.count, 0,
            "recentVisits should only contain completed visits (endedAt != nil).")
    }

    func testHistoryRange_LastNDays_FiltersOutOlderVisits() async throws {
        let cal = Calendar.current
        let oldDate = try XCTUnwrap(cal.date(byAdding: .day, value: -90, to: .now))
        seedCompletedVisit(at: oldDate, total: 99)
        seedCompletedVisit(at: .now, total: 30)

        let vm = ClientDetailViewModel(client: client, modelContext: context)
        await waitForFetch(vm)
        XCTAssertEqual(vm.recentVisits.count, 2, "Default `.all` range returns both.")

        vm.historyRange = .lastNDays(30)
        await waitForFetch(vm)

        XCTAssertEqual(vm.recentVisits.count, 1,
            "lastNDays(30) must filter out the 90-days-old visit.")
        XCTAssertEqual(vm.grandRevenue, Decimal(string: "30.00"))
    }

    func testLoadMore_BumpsPaginationLimit() async throws {
        for _ in 0..<8 {
            seedCompletedVisit(at: .now, total: 10)
        }

        // initialLimit=5 → first page returns 5, canLoadMore true, loadMore → 8 (all).
        let vm = ClientDetailViewModel(client: client, modelContext: context, initialLimit: 5)
        await waitForFetch(vm)
        XCTAssertEqual(vm.recentVisits.count, 5)
        XCTAssertTrue(vm.canLoadMore)

        vm.loadMore()
        await waitForFetch(vm)
        XCTAssertEqual(vm.recentVisits.count, 8)
        XCTAssertFalse(vm.canLoadMore)
    }

    func testActiveVisit_ReturnsOpenVisitForPet() async throws {
        let active = Visit(pet: pet)
        context.insert(active)
        try context.save()

        let vm = ClientDetailViewModel(client: client, modelContext: context)
        let found = vm.activeVisit(for: pet)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.uuid, active.uuid)
    }

    func testCheckIn_NoOpWhenActiveVisitAlreadyExists() async throws {
        let active = Visit(pet: pet, startedAt: .now)
        context.insert(active)
        try context.save()

        let vm = ClientDetailViewModel(client: client, modelContext: context)
        vm.checkIn(pet: pet, at: .now)
        // Wait for any internal Task to settle
        try await Task.sleep(for: .milliseconds(100))

        let activeVisits = (pet.visits ?? []).filter { $0.endedAt == nil }
        XCTAssertEqual(activeVisits.count, 1,
            "Calling checkIn while a visit is already active must not create a second one.")
    }

    func testVisitDidCompleteNotification_TriggersRefresh() async throws {
        let vm = ClientDetailViewModel(client: client, modelContext: context)
        await waitForFetch(vm)
        XCTAssertEqual(vm.recentVisits.count, 0)

        seedCompletedVisit(at: .now, total: 25)
        // Simulate a checkout completion posted by VisitRepository / CheckoutTransactionActor.
        NotificationCenter.default.post(
            name: .visitDidComplete,
            object: nil,
            userInfo: [VisitDidCompleteKey.clientID.rawValue: client.persistentModelID]
        )

        await waitForFetch(vm, expectVisits: 1)
        XCTAssertEqual(vm.recentVisits.count, 1,
            "ClientDetailVM must refresh when .visitDidComplete fires for this client.")
    }

    func testVisitDidCompleteNotification_OtherClient_DoesNotTriggerRefresh() async throws {
        let otherClient = Client(firstName: "Other", lastName: "Owner", phone: "5559998888")
        context.insert(otherClient)
        try context.save()

        let vm = ClientDetailViewModel(client: client, modelContext: context)
        await waitForFetch(vm)

        // Post a completion notification for a DIFFERENT client's visit.
        seedCompletedVisit(at: .now, total: 25)
        NotificationCenter.default.post(
            name: .visitDidComplete,
            object: nil,
            userInfo: [VisitDidCompleteKey.clientID.rawValue: otherClient.persistentModelID]
        )
        try await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(vm.recentVisits.count, 0,
            "VM must ignore .visitDidComplete events for other clients.")
    }

    // MARK: - Helpers

    /// `refreshRecentVisits` is non-async; poll `recentVisits.count` (or a custom predicate)
    /// to wait for the internal Task to finish populating data.
    private func waitForFetch(
        _ vm: ClientDetailViewModel,
        expectVisits: Int? = nil,
        timeout: TimeInterval = 2.0
    ) async {
        let start = Date()
        try? await Task.sleep(for: .milliseconds(50))
        while Date().timeIntervalSince(start) < timeout {
            if let target = expectVisits {
                if vm.recentVisits.count >= target { break }
            } else {
                // No explicit target — wait a short settle window.
                try? await Task.sleep(for: .milliseconds(100))
                break
            }
            try? await Task.sleep(for: .milliseconds(40))
        }
        try? await Task.sleep(for: .milliseconds(20))
    }

    @discardableResult
    private func seedCompletedVisit(at endedAt: Date, total: Decimal) -> Visit {
        let visit = Visit(pet: pet, startedAt: endedAt.addingTimeInterval(-1800))
        context.insert(visit)
        visit.addItem(title: "Bath", unitPrice: total)
        let payment = Payment(amount: total, method: .cash, paidAt: endedAt)
        context.insert(payment)
        visit.attachPayment(payment)
        visit.markCheckedOut(total: total, now: endedAt)
        try? context.save()
        return visit
    }
}
