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

    struct RevenueVisitData: Identifiable, Sendable {
        let id = UUID()
        let date: Date
        let petName: String
        let clientName: String
        let serviceSummary: String
        let total: Decimal
        let paymentMethod: String
    }

    struct ServiceProfitabilityData: Identifiable, Sendable {
        let id = UUID()
        let name: String
        let category: String
        let count: Int
        let revenue: Decimal
        let averageTicket: Decimal
        let trendPercent: Double
    }

    struct LapsedClientData: Identifiable, Sendable {
        let id: UUID
        let name: String
        let petNames: String
        let daysSinceLastVisit: Int
        let totalSpent: Decimal
        let phone: String?
        let primaryPetUUID: UUID?
        let suggestedMessage: String
    }

    struct ForecastData: Sendable {
        let projectedRevenue: Decimal
        let projectedVisits: Int
        let dailyAverageRevenue: Decimal
        let confidenceLabel: String
        let basis: String
    }

    struct ComparisonData: Identifiable, Sendable {
        let id = UUID()
        let label: String
        let currentRevenue: Decimal
        let previousRevenue: Decimal
        let currentVisits: Int
        let previousVisits: Int

        var revenueDelta: Decimal { currentRevenue - previousRevenue }
        var percentChange: Double {
            guard previousRevenue > .zero else { return currentRevenue > .zero ? 1 : 0 }
            return ((revenueDelta / previousRevenue) as NSDecimalNumber).doubleValue
        }
    }

    struct DataQualityIssue: Identifiable, Sendable {
        enum Severity: String, Sendable {
            case info
            case warning
            case critical
        }

        let id = UUID()
        let title: String
        let detail: String
        let count: Int
        let severity: Severity
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
    var revenueDrilldown:       [RevenueVisitData] = []
    var serviceProfitability:   [ServiceProfitabilityData] = []
    var lapsedClients:          [LapsedClientData] = []
    var forecast:               ForecastData?
    var comparisons:            [ComparisonData] = []
    var dataQualityIssues:      [DataQualityIssue] = []
    private(set) var isRefreshing  = false
    private(set) var isLoadingActionableInsights = false
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
    private var actionableInsightsTask: Task<Void, Never>?

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

        startActionableInsightsRefresh()
    }

    func refreshRevenue() async {
        revenueFetchTask?.cancel()
        revenueFetchTask = Task {
            await fetchRevenue()
            startActionableInsightsRefresh()
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

    func generateInsightsCSVDocument() -> ExportDocument {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())

        var rows: [[String]] = [
            ["Section", "Metric", "Value", "Detail"],
            ["Revenue", "\(revenuePeriodDays)-day total", totalRevenue.moneyString, "\(totalVisitsInPeriod) visits"],
            ["Revenue", "Average visit", averageVisitValue.moneyString, "\(revenuePeriodDays)-day window"],
            ["Retention", "Recurring clients", "\(Int(retentionRate * 100))%", "\(churnRiskCount) churn-risk clients"]
        ]

        if let forecast {
            rows.append(["Forecast", "Next 30 days", forecast.projectedRevenue.moneyString, "\(forecast.projectedVisits) projected visits"])
            rows.append(["Forecast", "Confidence", forecast.confidenceLabel, forecast.basis])
        }

        rows += comparisons.map {
            ["Comparison", $0.label, $0.currentRevenue.moneyString, "Previous: \($0.previousRevenue.moneyString), change: \(Self.percentString($0.percentChange))"]
        }

        rows += serviceProfitability.map {
            ["Service", $0.name, $0.revenue.moneyString, "\($0.count) sales, avg \($0.averageTicket.moneyString), trend \(Self.percentString($0.trendPercent))"]
        }

        rows += paymentMethodDistribution.map {
            ["Payment", $0.method.displayName, $0.amount.moneyString, "\($0.count) payments"]
        }

        rows += lapsedClients.map {
            ["Lapsed Client", $0.name, $0.totalSpent.moneyString, "\($0.daysSinceLastVisit) days since last visit; pets: \($0.petNames)"]
        }

        rows += dataQualityIssues.map {
            ["Data Quality", $0.title, "\($0.count)", $0.detail]
        }

        let csv = rows.map { row in
            row.map(\.csvEscaped).joined(separator: ",")
        }.joined(separator: "\n")

        return ExportDocument(csvData: csv + "\n", filename: "Pawtrackr_Insights_\(dateString).csv")
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

    private func fetchActionableInsights() async {
        let requestedPeriodDays = revenuePeriodDays
        isLoadingActionableInsights = true
        defer { isLoadingActionableInsights = false }

        do {
            let result = try await actor.fetchActionableInsights(periodDays: requestedPeriodDays)
            guard !Task.isCancelled, requestedPeriodDays == revenuePeriodDays else { return }
            revenueDrilldown = result.revenueDrilldown
            serviceProfitability = result.serviceProfitability
            lapsedClients = result.lapsedClients
            forecast = result.forecast
            comparisons = result.comparisons
            dataQualityIssues = result.dataQualityIssues
        } catch {
            Logger.insights.error("fetchActionableInsights failed: \(error)")
        }
    }

    private func startActionableInsightsRefresh() {
        actionableInsightsTask?.cancel()
        actionableInsightsTask = Task { [weak self] in
            guard let self else { return }
            await self.fetchActionableInsights()
        }
    }

    private static func percentString(_ value: Double) -> String {
        guard value.isFinite else { return "0%" }
        let sign = value > 0 ? "+" : ""
        return "\(sign)\(Int((value * 100).rounded()))%"
    }
}

private extension Logger {
    static let insights = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "Insights")
}
