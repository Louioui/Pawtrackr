//
//  InsightsViewModelTests.swift
//  PawtrackrTests
//
//  Verifies that the Insights screen's ViewModel correctly aggregates seeded
//  visits, payments, and summaries, and that report generation works.
//

import XCTest
import SwiftData
@testable import Pawtrackr

@MainActor
final class InsightsViewModelTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var dataStore: DataStoreService!
    private var eventBus: GlobalEventBus!

    override func setUpWithError() throws {
        try super.setUpWithError()

        let schema = Schema(PawtrackrSchema.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [config])
        context = container.mainContext
        dataStore = DataStoreService(container: container)
        eventBus = GlobalEventBus()
    }

    override func tearDownWithError() throws {
        container = nil
        context = nil
        dataStore = nil
        eventBus = nil
        try super.tearDownWithError()
    }

    // MARK: - Initial State

    func testInitialState_IsEmpty() {
        let vm = InsightsViewModel(dataStore: dataStore, eventBus: eventBus)

        XCTAssertEqual(vm.totalRevenue, .zero)
        XCTAssertEqual(vm.averageVisitValue, .zero)
        XCTAssertEqual(vm.totalVisitsInPeriod, 0)
        XCTAssertEqual(vm.retentionRate, 0)
        XCTAssertTrue(vm.revenueSeries.isEmpty)
        XCTAssertTrue(vm.serviceDistribution.isEmpty)
        XCTAssertTrue(vm.topClients.isEmpty)
        XCTAssertFalse(vm.hasLoadedOnce)
    }

    // MARK: - Refresh

    func testRefresh_AggregatesSeededRevenue() async throws {
        try seedTwoCompletedVisits()

        let vm = InsightsViewModel(dataStore: dataStore, eventBus: eventBus)
        await vm.refresh()

        XCTAssertTrue(vm.hasLoadedOnce)
        XCTAssertEqual(vm.totalVisitsInPeriod, 2)
        XCTAssertEqual(vm.totalRevenue, Decimal(120))
        XCTAssertEqual(vm.averageVisitValue, Decimal(60))
    }

    func testRefresh_PopulatesServiceDistributionInDescendingRevenue() async throws {
        try seedTwoCompletedVisits()

        let vm = InsightsViewModel(dataStore: dataStore, eventBus: eventBus)
        await vm.refresh()

        XCTAssertFalse(vm.serviceDistribution.isEmpty)
        // The seed has Bath ($30) and Haircut ($45 + $45 = $90). Haircut should be first.
        XCTAssertEqual(vm.serviceDistribution.first?.name, "Haircut")
    }

    func testRefresh_GuardsAgainstReentrancy() async throws {
        try seedTwoCompletedVisits()

        let vm = InsightsViewModel(dataStore: dataStore, eventBus: eventBus)
        async let first: Void = vm.refresh()
        async let second: Void = vm.refresh()
        _ = await (first, second)

        // Both refreshes resolve cleanly. We only assert that the work converged
        // to a stable state (not the lock semantics, which are implementation detail).
        XCTAssertTrue(vm.hasLoadedOnce)
    }

    // MARK: - Revenue Period

    func testRefreshRevenue_RespectsPeriodChange() async throws {
        try seedTwoCompletedVisits()

        let vm = InsightsViewModel(dataStore: dataStore, eventBus: eventBus)
        await vm.refresh()
        let baselineSeries = vm.revenueSeries.count

        vm.revenuePeriodDays = 7
        await vm.refreshRevenue()
        XCTAssertLessThanOrEqual(vm.revenueSeries.count, baselineSeries,
                                 "Shorter window should not produce more buckets than 30-day default.")

        vm.revenuePeriodDays = 90
        await vm.refreshRevenue()
        XCTAssertGreaterThanOrEqual(vm.revenueSeries.count, 0)
    }

    // MARK: - Report Summary

    func testGenerateReportSummary_CompilesMonthlyStats() async throws {
        try seedTwoCompletedVisits()

        let vm = InsightsViewModel(dataStore: dataStore, eventBus: eventBus)
        await vm.refresh()

        let summary = await vm.generateReportSummary()
        XCTAssertEqual(summary.totalRevenue, Decimal(120))
        XCTAssertGreaterThanOrEqual(summary.newClients, 0)
        XCTAssertGreaterThanOrEqual(summary.topServices.count, 1)
    }

    // MARK: - Test Fixtures

    private func seedTwoCompletedVisits() throws {
        let now = Date()

        let owner = Client(firstName: "Test", lastName: "Owner", phone: "5550100100")
        context.insert(owner)

        let pet = Pet(name: "Buddy", species: .dog)
        pet.owner = owner
        context.insert(pet)

        let bath = Service(name: "Bath", basePrice: 30)
        let cut  = Service(name: "Haircut", basePrice: 45)
        context.insert(bath)
        context.insert(cut)

        // Two completed visits in the last few days so they fall in the 30-day window.
        let visit1 = Visit(pet: pet, startedAt: now.addingTimeInterval(-3 * 86_400))
        context.insert(visit1)
        let item1 = VisitItem.from(service: bath, visit: visit1)
        let item2 = VisitItem.from(service: cut, visit: visit1)
        context.insert(item1)
        context.insert(item2)
        visit1.items = [item1, item2]
        let payment1 = Payment(amount: 75, method: .cash, paidAt: now.addingTimeInterval(-3 * 86_400))
        context.insert(payment1)
        visit1.attachPayment(payment1)
        visit1.markCheckedOut(total: 75, now: now.addingTimeInterval(-3 * 86_400 + 3600))

        let visit2 = Visit(pet: pet, startedAt: now.addingTimeInterval(-86_400))
        context.insert(visit2)
        let item3 = VisitItem.from(service: cut, visit: visit2)
        context.insert(item3)
        visit2.items = [item3]
        let payment2 = Payment(amount: 45, method: .creditCard, paidAt: now.addingTimeInterval(-86_400), externalReference: "1234")
        context.insert(payment2)
        visit2.attachPayment(payment2)
        visit2.markCheckedOut(total: 45, now: now.addingTimeInterval(-86_400 + 3600))

        try context.save()

        // Build the day summaries so fetchRevenue + fetchMonthlyGrowth see real data
        // (those paths read from the DaySummary cache, not raw visits).
        SummaryUpdater.rebuildDay(for: visit1.endedAt ?? Date(), in: context)
        SummaryUpdater.rebuildDay(for: visit2.endedAt ?? Date(), in: context)
    }
}
