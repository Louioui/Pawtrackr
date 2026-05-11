import XCTest
import SwiftData
@testable import Pawtrackr

/// Coverage for RecentHistoryViewModel — the cross-pet recent-visits feed.
/// Verifies fetch fills groupedVisits/sortedDays, scope filters by date,
/// query filters by pet/owner/service name, and CSV export shape.
@MainActor
final class RecentHistoryViewModelTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var dataStore: DataStoreService!
    var eventBus: GlobalEventBus!
    var client: Client!
    var pet: Pet!

    override func setUpWithError() throws {
        let schema = Schema(PawtrackrSchema.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [config])
        context = container.mainContext
        dataStore = DataStoreService(container: container)
        eventBus = GlobalEventBus()

        client = Client(firstName: "Jane", lastName: "Doe", phone: "5551234567")
        context.insert(client)
        pet = Pet(name: "Buddy", species: .dog)
        pet.owner = client
        context.insert(pet)
        try context.save()

        Formatters.updateCurrencySymbol("$")
    }

    override func tearDownWithError() throws {
        container = nil; context = nil; dataStore = nil; eventBus = nil; client = nil; pet = nil
    }

    func testFetchVisits_AllScope_GroupsByDayAndSumsRevenue() async throws {
        let cal = Calendar.current
        let yesterday = try XCTUnwrap(cal.date(byAdding: .day, value: -1, to: .now))
        seedCheckedOutVisit(pet: pet, endedAt: .now, total: 30)
        seedCheckedOutVisit(pet: pet, endedAt: yesterday, total: 20)

        let vm = RecentHistoryViewModel(dataStore: dataStore, eventBus: eventBus)
        vm.fetchVisits()
        await waitForFetch(vm)

        XCTAssertEqual(vm.summaryVisitCount, 2)
        XCTAssertEqual(vm.summaryRevenueString, "$50.00")
        XCTAssertEqual(vm.sortedDays.count, 2, "Two distinct days produce two day groupings.")
        XCTAssertEqual(vm.sortedDays.first, cal.startOfDay(for: .now),
            "sortedDays must be in descending order — today before yesterday.")
    }

    func testFetchVisits_TodayScope_ExcludesYesterday() async throws {
        let yesterday = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -1, to: .now))
        seedCheckedOutVisit(pet: pet, endedAt: .now, total: 30)
        seedCheckedOutVisit(pet: pet, endedAt: yesterday, total: 20)

        let vm = RecentHistoryViewModel(dataStore: dataStore, eventBus: eventBus)
        vm.scope = .today
        vm.fetchVisits()
        await waitForFetch(vm)

        XCTAssertEqual(vm.summaryVisitCount, 1)
        XCTAssertEqual(vm.summaryRevenueString, "$30.00")
    }

    func testQuery_FiltersByPetName() async throws {
        let lucy = Pet(name: "Lucy", species: .dog)
        lucy.owner = client
        context.insert(lucy)
        try context.save()

        seedCheckedOutVisit(pet: pet, endedAt: .now, total: 30)
        seedCheckedOutVisit(pet: lucy, endedAt: .now, total: 40)

        let vm = RecentHistoryViewModel(dataStore: dataStore, eventBus: eventBus)
        vm.fetchVisits()
        await waitForFetch(vm)
        XCTAssertEqual(vm.summaryVisitCount, 2)

        vm.query = "Lucy"
        // Debounce is 300ms — wait past it and then for fetch to settle.
        try await Task.sleep(for: .milliseconds(400))
        await waitForFetch(vm)

        XCTAssertEqual(vm.summaryVisitCount, 1, "Query must filter results down to the matching pet.")
    }

    func testExportCSV_HasHeaderAndIncludesVisitFields() async throws {
        seedCheckedOutVisit(pet: pet, endedAt: .now, services: ["Bath"], total: 30, reference: "1234")

        let vm = RecentHistoryViewModel(dataStore: dataStore, eventBus: eventBus)
        vm.fetchVisits()
        await waitForFetch(vm)

        let csv = vm.exportCSV()
        XCTAssertTrue(csv.hasPrefix("VisitID,StartedAt,EndedAt,Pet,Owner,Services,Amount,Payment,Reference,Notes"))
        XCTAssertTrue(csv.contains("Buddy"))
        XCTAssertTrue(csv.contains("Bath"))
        XCTAssertTrue(csv.contains("1234"))
    }

    // MARK: - Helpers

    /// The VM fires its fetch on a Task. Poll until isLoading flips false (or timeout).
    private func waitForFetch(_ vm: RecentHistoryViewModel, timeout: TimeInterval = 2.0) async {
        let start = Date()
        // Wait briefly to let the Task scheduling start.
        try? await Task.sleep(for: .milliseconds(20))
        while vm.isLoading {
            try? await Task.sleep(for: .milliseconds(20))
            if Date().timeIntervalSince(start) > timeout { return }
        }
        // Settle.
        try? await Task.sleep(for: .milliseconds(20))
    }

    @discardableResult
    private func seedCheckedOutVisit(
        pet: Pet,
        endedAt: Date,
        services: [String] = ["Bath"],
        total: Decimal,
        reference: String? = nil
    ) -> Visit {
        let visit = Visit(pet: pet, startedAt: endedAt.addingTimeInterval(-1800))
        context.insert(visit)
        let perItem = total / Decimal(max(1, services.count))
        for s in services {
            visit.addItem(title: s, unitPrice: perItem)
        }
        let payment = Payment(amount: total, method: .cash, paidAt: endedAt, externalReference: reference)
        context.insert(payment)
        visit.attachPayment(payment)
        visit.markCheckedOut(total: total, now: endedAt)
        try? context.save()
        return visit
    }
}
