import XCTest
import SwiftData
@testable import Pawtrackr

/// Coverage for the PetHistoryViewModel — the screen groomers open most often to look
/// up an individual pet's past visits. Verifies scope filtering, search filtering,
/// KPI math, "must be paid to appear" rule, and CSV export.
@MainActor
final class PetHistoryViewModelTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var client: Client!
    var pet: Pet!
    var otherPet: Pet!

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
        otherPet = Pet(name: "Lucy", species: .dog)
        otherPet.owner = client
        context.insert(otherPet)
        try context.save()

        Formatters.updateCurrencySymbol("$")
    }

    override func tearDownWithError() throws {
        container = nil; context = nil; client = nil; pet = nil; otherPet = nil
    }

    func testRefresh_ReturnsOnlyTargetPetsVisits() async throws {
        seedCheckedOutVisit(pet: pet, endedAt: .now, total: 30)
        seedCheckedOutVisit(pet: otherPet, endedAt: .now, total: 50)

        let vm = PetHistoryViewModel(pet: pet, modelContext: context)
        // Default scope is .thisMonth which includes .now. Avoid scope change
        // to skip the scheduleRefresh() race against our explicit refresh.
        await vm.refresh()

        XCTAssertEqual(vm.visits.count, 1, "Only the target pet's visits should appear.")
        XCTAssertEqual(vm.totalVisits, 1)
        XCTAssertEqual(vm.totalSpent, Decimal(string: "30.00"))
    }

    func testRefresh_ExcludesVisitsWithoutPayment() async throws {
        // Visit without payment — must NOT appear in pet history.
        let unpaid = Visit(pet: pet, startedAt: Date().addingTimeInterval(-1800))
        context.insert(unpaid)
        unpaid.markCheckedOut(total: 25.00)
        try context.save()

        let vm = PetHistoryViewModel(pet: pet, modelContext: context)
        await vm.refresh()

        XCTAssertEqual(vm.visits.count, 0,
            "Unpaid visits must not appear — Pet History only shows transactions with a Payment record.")
    }

    func testScope_Today_FiltersOutYesterdayVisits() async throws {
        let cal = Calendar.current
        let yesterday = try XCTUnwrap(cal.date(byAdding: .day, value: -1, to: .now))
        seedCheckedOutVisit(pet: pet, endedAt: yesterday, total: 50)
        seedCheckedOutVisit(pet: pet, endedAt: .now, total: 30)

        let vm = PetHistoryViewModel(pet: pet, modelContext: context)
        vm.scope = .today
        await waitForSettled(vm)

        XCTAssertEqual(vm.visits.count, 1)
        XCTAssertEqual(vm.totalSpent, Decimal(string: "30.00"))
    }

    func testScope_All_ReturnsAcrossDateRange() async throws {
        let cal = Calendar.current
        let monthsAgo = try XCTUnwrap(cal.date(byAdding: .month, value: -3, to: .now))
        seedCheckedOutVisit(pet: pet, endedAt: monthsAgo, total: 25)
        seedCheckedOutVisit(pet: pet, endedAt: .now, total: 30)

        let vm = PetHistoryViewModel(pet: pet, modelContext: context)
        vm.scope = .all
        await waitForSettled(vm)

        XCTAssertEqual(vm.visits.count, 2)
        XCTAssertEqual(vm.totalSpent, Decimal(string: "55.00"))
    }

    func testSearch_FiltersByServiceName() async throws {
        seedCheckedOutVisit(pet: pet, endedAt: .now, services: ["Bath"], total: 30)
        seedCheckedOutVisit(pet: pet, endedAt: .now, services: ["Nail Trim"], total: 15)

        let vm = PetHistoryViewModel(pet: pet, modelContext: context)
        await vm.refresh()
        XCTAssertEqual(vm.filtered.count, 2)

        vm.searchText = "Bath"
        XCTAssertEqual(vm.filtered.count, 1)
        XCTAssertEqual(vm.totalSpent, Decimal(string: "30.00"),
            "KPIs must reflect filtered set, not raw history.")
    }

    func testSearch_FiltersByExternalReference() async throws {
        seedCheckedOutVisit(pet: pet, endedAt: .now, services: ["Bath"], total: 30, reference: "ZELLE-99")
        seedCheckedOutVisit(pet: pet, endedAt: .now, services: ["Bath"], total: 30, reference: "ZELLE-42")

        let vm = PetHistoryViewModel(pet: pet, modelContext: context)
        await vm.refresh()
        XCTAssertEqual(vm.filtered.count, 2)

        vm.searchText = "ZELLE-99"
        XCTAssertEqual(vm.filtered.count, 1)
    }

    func testKPIs_AverageDurationReflectsCheckedInToOutSpan() async throws {
        seedCheckedOutVisit(pet: pet, endedAt: .now, total: 30, durationSec: 1800)   // 30 min
        seedCheckedOutVisit(pet: pet, endedAt: .now, total: 50, durationSec: 3600)   // 60 min

        let vm = PetHistoryViewModel(pet: pet, modelContext: context)
        await vm.refresh()

        XCTAssertEqual(vm.averageDuration, 2700, accuracy: 1.0,
            "Average duration should be (1800+3600)/2 = 2700s.")
    }

    func testExportCSV_HasHeaderAndOneRowPerVisit() async throws {
        seedCheckedOutVisit(pet: pet, endedAt: .now, services: ["Bath"], total: 30)
        seedCheckedOutVisit(pet: pet, endedAt: .now, services: ["Nail Trim"], total: 15)

        let vm = PetHistoryViewModel(pet: pet, modelContext: context)
        await vm.refresh()

        let csvData = vm.exportCSV()
        let csv = try XCTUnwrap(String(data: csvData, encoding: .utf8))
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: false)

        XCTAssertEqual(lines.first, "Date,Services,Duration,Amount")
        XCTAssertEqual(lines.count, 3, "1 header + 2 rows.")
    }

    // MARK: - Concurrency helper

    /// Setting `vm.scope` triggers an internal `scheduleRefresh()` that races with any
    /// explicit `await vm.refresh()`. Wait for `isLoading` to settle so the latest
    /// refresh's results are populated before assertions run.
    private func waitForSettled(_ vm: PetHistoryViewModel, timeout: TimeInterval = 2.0) async {
        let start = Date()
        // Give the scheduled Task a moment to start (flip isLoading to true).
        try? await Task.sleep(for: .milliseconds(50))
        while vm.isLoading {
            try? await Task.sleep(for: .milliseconds(20))
            if Date().timeIntervalSince(start) > timeout { return }
        }
        // Small settle for the @Observable to publish.
        try? await Task.sleep(for: .milliseconds(20))
    }

    // MARK: - Helpers

    @discardableResult
    private func seedCheckedOutVisit(
        pet: Pet,
        endedAt: Date,
        services: [String] = ["Bath"],
        total: Decimal,
        durationSec: TimeInterval = 1800,
        reference: String? = nil
    ) -> Visit {
        let visit = Visit(pet: pet, startedAt: endedAt.addingTimeInterval(-durationSec))
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
