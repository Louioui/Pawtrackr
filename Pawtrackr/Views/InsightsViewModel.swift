//
//  InsightsViewModel.swift
//  Pawtrackr
//

import Foundation
import SwiftData
import Observation
import OSLog
import SwiftUI

@Observable
@MainActor
class InsightsViewModel {
    
    enum State: Equatable {
        case loading
        case loaded
        case error(String)
    }

    struct RevenueData: Identifiable, Sendable {
        let id = UUID()
        let date: Date
        let amount: Decimal
    }

    struct DistributionData: Identifiable, Sendable {
        let id = UUID()
        let name: String
        let count: Int
        var revenue: Decimal = .zero
    }

    struct PaymentMethodData: Identifiable, Sendable {
        let id = UUID()
        let method: Payment.Method
        let count: Int
        let amount: Decimal
    }

    struct MonthlyGrowthData: Identifiable, Sendable {
        let id = UUID()
        let month: String
        let revenue: Decimal
        let visitCount: Int
    }

    struct TopClientData: Identifiable, Sendable {
        let id = UUID()
        let name: String
        let totalSpent: Decimal
        let visitCount: Int
    }

    struct RetentionData: Identifiable, Sendable {
        let id = UUID()
        let label: String
        let value: Double
    }

    // MARK: - State
    var state: State = .loading
    var revenueSeries:          [RevenueData]       = []
    var serviceDistribution:    [DistributionData]  = []
    var categoryDistribution:   [DistributionData]  = []
    var paymentMethodDistribution: [PaymentMethodData] = []
    var topClients:             [TopClientData]     = []
    var monthlyGrowth:          [MonthlyGrowthData] = []
    var retentionRate:          Double  = 0
    var churnRiskCount:         Int     = 0
    var retentionSeries:        [RetentionData]     = []
    var totalRevenue:           Decimal = .zero
    var averageVisitValue:      Decimal = .zero
    var totalVisitsInPeriod:    Int     = 0
    var revenuePeriodDays:      Int     = 30
    private(set) var isRefreshing  = false
    /// Becomes true once `refresh()` completes successfully at least once.
    /// Stays true across subsequent refreshes — even failing ones — because
    /// the user has already seen real data and the empty/loading skeleton
    /// should not reappear.
    private(set) var hasLoadedOnce = false

    private let dataStore: DataStoreService
    private let eventBus: GlobalEventBus
    private let actor: InsightsActor
    private var observationTask: Task<Void, Never>?
    private var revenueFetchTask: Task<Void, Never>?

    init(dataStore: DataStoreService, eventBus: GlobalEventBus = GlobalEventBus()) {
        self.dataStore = dataStore
        self.eventBus = eventBus
        self.actor = InsightsActor(modelContainer: dataStore.container)
        
        self.observationTask = Task { [weak self] in
            for await event in eventBus.stream {
                guard let self else { return }
                switch event {
                case .checkoutCompleted(_), .refreshRequired:
                    await self.refresh()
                default:
                    break
                }
            }
        }
    }

    deinit {
        // Task.cancel() is thread-safe.
    }

    // MARK: - Public

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        await PerformanceMonitor.measureAsyncNoThrow(label: "Insights.refresh") {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await self.fetchRevenue() }
                group.addTask { await self.fetchMonthlyGrowth() }
                group.addTask { await self.fetchDistributions() }
                group.addTask { await self.fetchClientInsights() }
            }
        }

        hasLoadedOnce = true
        withAnimation(.spring()) {
            state = .loaded
        }
    }

    func refreshRevenue() async {
        revenueFetchTask?.cancel()
        revenueFetchTask = Task {
            await fetchRevenue()
        }
        await revenueFetchTask?.value
    }

    func generateReportSummary() async -> BusinessReportService.MonthlySummary {
        let now = Date()
        let cal = Calendar.current
        let startOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now

        let topSvc = serviceDistribution.prefix(5).map {
            (name: $0.name, count: $0.count, revenue: $0.revenue)
        }

        let fmt = DateFormatter()
        fmt.dateFormat = "MMM"
        let currentMonthLabel = fmt.string(from: now)
        let monthlyVisits = monthlyGrowth.first(where: { $0.month == currentMonthLabel })?.visitCount ?? 0

        let container = dataStore.container
        let newClientsCount: Int = await Task.detached(priority: .utility) {
            let bg = ModelContext(container)
            let descriptor = FetchDescriptor<Client>(
                predicate: #Predicate<Client> { $0.createdAt >= startOfMonth }
            )
            return (try? bg.fetchCount(descriptor)) ?? 0
        }.value

        return BusinessReportService.MonthlySummary(
            month: now,
            totalRevenue: totalRevenue,
            visitCount: monthlyVisits,
            newClients: newClientsCount,
            topServices: topSvc,
            retentionRate: retentionRate
        )
    }

    // MARK: - Actor Delegations

    private func fetchRevenue() async {
        do {
            let result = try await actor.fetchRevenue(periodDays: revenuePeriodDays)
            revenueSeries = result.series
            totalRevenue = result.totalRevenue
            totalVisitsInPeriod = result.totalVisits
            averageVisitValue = result.averageVisitValue
        } catch {
            Logger.insights.error("fetchRevenue failed: \(error)")
        }
    }

    private func fetchDistributions() async {
        do {
            let result = try await actor.fetchDistributions()
            serviceDistribution = result.services
            categoryDistribution = result.categories
            paymentMethodDistribution = result.payments
        } catch {
            Logger.insights.error("fetchDistributions failed: \(error)")
        }
    }

    private func fetchClientInsights() async {
        do {
            let result = try await actor.fetchClientInsights()
            topClients = result.topClients
            retentionRate = result.retentionRate
            churnRiskCount = result.churnRiskCount
            retentionSeries = result.retentionSeries
        } catch {
            Logger.insights.error("fetchClientInsights failed: \(error)")
        }
    }

    private func fetchMonthlyGrowth() async {
        do {
            monthlyGrowth = try await actor.fetchMonthlyGrowth()
        } catch {
            Logger.insights.error("fetchMonthlyGrowth failed: \(error)")
        }
    }
}

private extension Logger {
    static let insights = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "Insights")
}
