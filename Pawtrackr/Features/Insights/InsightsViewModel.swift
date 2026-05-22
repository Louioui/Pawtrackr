//
//  InsightsViewModel.swift
//  Pawtrackr
//

import Foundation
import SwiftData
import Observation
import OSLog
import SwiftUI
import CoreData

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
    var dataQualityIssues:      [DataQualityIssue] = []
    private(set) var isRefreshing  = false
    private(set) var isLoadingActionableInsights = false
    /// Becomes true once `refresh()` completes successfully at least once.
    /// Stays true across subsequent refreshes — even failing ones — because
    /// the user has already seen real data and the empty/loading skeleton
    /// should not reappear.
    private(set) var hasLoadedOnce = false

    var totalCategoryVisits: Int {
        categoryDistribution.reduce(0) { $0 + $1.count }
    }

    private let dataStore: DataStoreService
    private let eventBus: GlobalEventBus
    private let actor: InsightsActor
    private var observationTask: Task<Void, Never>?
    private var revenueFetchTask: Task<Void, Never>?
    private var actionableInsightsTask: Task<Void, Never>?
    private var refreshDebounceTask: Task<Void, Never>?

    init(dataStore: DataStoreService, eventBus: GlobalEventBus = GlobalEventBus()) {
        self.dataStore = dataStore
        self.eventBus = eventBus
        self.actor = InsightsActor(modelContainer: dataStore.container)

        self.observationTask = Task { [weak self] in
            for await event in eventBus.stream {
                guard let self else { return }
                switch event {
                case .checkoutCompleted(_):
                    // Checkout completion: refresh immediately so the user sees updated totals.
                    await self.refresh()
                case .refreshRequired:
                    // CloudKit syncs can fire dozens of these in rapid succession.
                    // Coalesce them into one refresh once the burst settles.
                    self.refreshDebounceTask?.cancel()
                    self.refreshDebounceTask = Task { [weak self] in
                        try? await Task.sleep(for: .milliseconds(800))
                        guard let self, !Task.isCancelled else { return }
                        await self.refresh()
                    }
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

        _ = await PerformanceMonitor.measureAsyncNoThrow(label: "Insights.refresh") {
            try? await Task.sleep(for: .milliseconds(500)) // Yield to allow UI to render 'loading' state
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await self.fetchRevenue() }
                group.addTask { await self.fetchMonthlyGrowth() }
                group.addTask { await self.fetchDistributions() }
                group.addTask { await self.fetchClientInsights() }
            }
        }

        if !hasLoadedOnce && revenueSeries.isEmpty && serviceDistribution.isEmpty {
            // If we have no data and nothing was loaded, it might be an error or just empty.
            // We check if an error occurred during the refresh.
            // For now, we'll just ensure the state is 'loaded' so the empty states show,
            // unless a specific fetch error was logged.
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

    struct ExportSnapshot: Sendable {
        let dateString: String
        let totalRevenue: String
        let totalVisits: Int
        let revenuePeriodDays: Int
        let averageVisitValue: String
        let retentionRate: Int
        let churnRiskCount: Int
        let serviceProfitability: [(name: String, revenue: String, count: Int, avg: String, trend: String)]
        let paymentMix: [(method: String, amount: String, count: Int)]
        let qualityIssues: [(title: String, count: Int, detail: String)]
    }

    @MainActor
    private func makeExportSnapshot() -> ExportSnapshot {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        return ExportSnapshot(
            dateString: dateFormatter.string(from: Date()),
            totalRevenue: totalRevenue.moneyString,
            totalVisits: totalVisitsInPeriod,
            revenuePeriodDays: revenuePeriodDays,
            averageVisitValue: averageVisitValue.moneyString,
            retentionRate: Int((retentionRate * 100).clampedToValueRange()),
            churnRiskCount: churnRiskCount,
            serviceProfitability: serviceProfitability.map { ($0.name, $0.revenue.moneyString, $0.count, $0.averageTicket.moneyString, Self.percentString($0.trendPercent)) },
            paymentMix: paymentMethodDistribution.map { ($0.method.displayName, $0.amount.moneyString, $0.count) },
            qualityIssues: dataQualityIssues.map { ($0.title, $0.count, $0.detail) }
        )
    }

    @MainActor
    func generateInsightsCSVDocument() async -> ExportDocument {
        let snapshot = makeExportSnapshot()
        
        return await Task.detached(priority: .userInitiated) {
            var rows: [[String]] = [
                [
                    NSLocalizedString("insights.csv.header.section", value: "Section", comment: ""),
                    NSLocalizedString("insights.csv.header.metric", value: "Metric", comment: ""),
                    NSLocalizedString("insights.csv.header.value", value: "Value", comment: ""),
                    NSLocalizedString("insights.csv.header.detail", value: "Detail", comment: "")
                ],
                [
                    NSLocalizedString("insights.csv.section.revenue", value: "Revenue", comment: ""),
                    String(format: NSLocalizedString("insights.csv.metric.revenue_total_fmt", value: "%d-day total", comment: ""), snapshot.revenuePeriodDays),
                    snapshot.totalRevenue,
                    String(format: NSLocalizedString("insights.csv.detail.visits_fmt", value: "%d visits", comment: ""), snapshot.totalVisits)
                ],
                [
                    NSLocalizedString("insights.csv.section.revenue", value: "Revenue", comment: ""),
                    NSLocalizedString("insights.csv.metric.average_visit", value: "Average visit", comment: ""),
                    snapshot.averageVisitValue,
                    String(format: NSLocalizedString("insights.csv.detail.window_fmt", value: "%d-day window", comment: ""), snapshot.revenuePeriodDays)
                ],
                [
                    NSLocalizedString("insights.csv.section.retention", value: "Retention", comment: ""),
                    NSLocalizedString("insights.csv.metric.recurring_clients", value: "Recurring clients", comment: ""),
                    "\(snapshot.retentionRate)%",
                    String(format: NSLocalizedString("insights.csv.detail.churn_risk_fmt", value: "%d churn-risk clients", comment: ""), snapshot.churnRiskCount)
                ]
            ]

            rows += snapshot.serviceProfitability.map {
                [
                    NSLocalizedString("insights.csv.section.service", value: "Service", comment: ""),
                    $0.name,
                    $0.revenue,
                    String(
                        format: NSLocalizedString("insights.csv.detail.service_profitability_fmt", value: "%d sales, avg %@, trend %@", comment: ""),
                        $0.count,
                        $0.avg,
                        $0.trend
                    )
                ]
            }

            rows += snapshot.paymentMix.map {
                [
                    NSLocalizedString("insights.csv.section.payment", value: "Payment", comment: ""),
                    $0.method,
                    $0.amount,
                    String(format: NSLocalizedString("insights.csv.detail.payments_fmt", value: "%d payments", comment: ""), $0.count)
                ]
            }

            rows += snapshot.qualityIssues.map {
                [
                    NSLocalizedString("insights.csv.section.data_quality", value: "Data Quality", comment: ""),
                    $0.title,
                    "\($0.count)",
                    $0.detail
                ]
            }

            let csv = rows.map { row in
                row.map(\.csvEscaped).joined(separator: ",")
            }.joined(separator: "\n")

            return ExportDocument(csvData: csv + "\n", filename: "Pawtrackr_Insights_\(snapshot.dateString).csv")
        }.value
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
        let clampedValue = max(Double(Int.min) / 100.0, min(Double(Int.max) / 100.0, value))
        return "\(sign)\(Int((clampedValue * 100).rounded()))%"
    }
}

private extension Double {
    func clampedToValueRange() -> Double {
        guard self.isFinite else { return 0 }
        return max(Double(Int.min), min(Double(Int.max), self))
    }
}

private extension Logger {
    static let insights = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "Insights")
}
