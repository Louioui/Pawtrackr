//
//  InsightsViewModel.swift
//  Pawtrackr
//
//  All DB fetches that traverse relationships use relationshipKeyPathsForPrefetching
//  to batch-load related objects in one SQL query (eliminates N+1 round-trips).
//

import Foundation
import SwiftData
import Observation
import OSLog

@Observable
@MainActor
class InsightsViewModel {
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

    private struct ClientInsightsResult: Sendable {
        let topClients: [TopClientData]
        let retentionRate: Double
        let churnRiskCount: Int
        let retentionSeries: [RetentionData]
    }

    // MARK: - State
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
    private(set) var hasLoadedOnce = false

    private let dataStore: DataStoreService
    private let eventBus: GlobalEventBus
    private var observationTask: Task<Void, Never>?
    /// In-flight revenue fetch. Cancelled and replaced when the user changes the
    /// period picker so rapid 7→30→90 taps don't race and leave stale data on screen.
    private var revenueFetchTask: Task<Void, Never>?

    init(dataStore: DataStoreService, eventBus: GlobalEventBus = GlobalEventBus()) {
        self.dataStore = dataStore
        self.eventBus = eventBus
        // Use weak self so the observation task does not retain the VM. When the
        // view dismisses and the VM is deallocated, the next yielded event finds
        // self == nil and breaks the loop, ending the task naturally.
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

    // MARK: - Public

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        // Load the metrics needed to render the screen first. The client-wide
        // metrics can touch far more rows, so they run after the first paint.
        await fetchRevenue()
        await fetchMonthlyGrowth()
        await fetchDistributions()
        hasLoadedOnce = true
        await fetchClientInsights()
    }

    func refreshRevenue() async {
        // Cancel any in-flight fetch from a prior period change so we don't write
        // stale results into revenueSeries after the user has moved on.
        revenueFetchTask?.cancel()
        let task = Task { await fetchRevenue() }
        revenueFetchTask = task
        await task.value
    }

    func generateReportSummary() async -> BusinessReportService.MonthlySummary {
        let now = Date()
        let cal = Calendar.current
        let startOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now

        let topSvc = serviceDistribution.prefix(5).map {
            (name: $0.name, count: $0.count, revenue: $0.revenue)
        }

        // Use the same DateFormatter as fetchMonthlyGrowth so the month label matches.
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM"
        let currentMonthLabel = fmt.string(from: now)
        let monthlyVisits = monthlyGrowth.first(where: { $0.month == currentMonthLabel })?.visitCount ?? 0

        let descriptor = FetchDescriptor<Client>(
            predicate: #Predicate<Client> { $0.createdAt >= startOfMonth }
        )
        let newClientsCount: Int
        do {
            newClientsCount = try dataStore.container.mainContext.fetchCount(descriptor)
        } catch {
            Logger.insights.error("New clients count fetch failed: \(String(describing: error))")
            newClientsCount = 0
        }

        return BusinessReportService.MonthlySummary(
            month: now,
            totalRevenue: totalRevenue,
            visitCount: monthlyVisits,
            newClients: newClientsCount,
            topServices: topSvc,
            retentionRate: retentionRate
        )
    }

    // MARK: - Private fetches

    private func fetchRevenue() async {
        let periodDays = revenuePeriodDays
        let cal        = Calendar.current
        let end        = cal.startOfDay(for: .now)
        guard let start = cal.date(byAdding: .day, value: -(periodDays - 1), to: end) else { return }

        let container = dataStore.container
        let aggregates = await Task.detached(priority: .utility) { () -> [SummaryUpdater.DayAggregate] in
            let bgContext = ModelContext(container)
            var descriptor = FetchDescriptor<DaySummary>(
                predicate: #Predicate<DaySummary> { summary in
                    summary.day >= start && summary.day <= end
                }
            )
            // Predicate already constrains to <= 90 days; this fetchLimit is a safety
            // valve in case the summary table has duplicates from a legacy migration.
            descriptor.fetchLimit = 500
            let summaries: [DaySummary]
            do {
                summaries = try bgContext.fetch(descriptor)
            } catch {
                Logger.insights.error("Revenue DaySummary fetch failed: \(String(describing: error))")
                summaries = []
            }
            return SummaryUpdater.collapsedDayAggregates(from: summaries).values.sorted { $0.day < $1.day }
        }.value

        // If a newer period change cancelled this task while the background fetch
        // was running, abandon the result so we don't flicker stale data on screen.
        if Task.isCancelled { return }

        let totalVisits = aggregates.reduce(0) { $0 + $1.visitCount }

        revenueSeries       = aggregates.map { RevenueData(date: $0.day, amount: $0.revenue) }
        totalRevenue        = aggregates.reduce(.zero) { $0 + $1.revenue }
        totalVisitsInPeriod = totalVisits
        averageVisitValue   = totalVisits > 0
            ? totalRevenue / Decimal(totalVisits)
            : .zero
    }

    private func fetchDistributions() async {
        let container = dataStore.container
        let cal   = Calendar.current
        let end   = cal.startOfDay(for: .now).addingTimeInterval(86400)
        let start = cal.date(byAdding: .day, value: -30, to: end) ?? end

        let result = await Task.detached(priority: .utility) {
            () -> (services: [DistributionData], categories: [DistributionData], payments: [PaymentMethodData]) in

            let bgContext = ModelContext(container)

            var visitsDescriptor = FetchDescriptor<Visit>(
                predicate: #Predicate<Visit> { visit in
                    if let endedAt = visit.endedAt {
                        endedAt >= start && endedAt < end
                    } else {
                        false
                    }
                },
                sortBy: [SortDescriptor(\.endedAt, order: .reverse)]
            )
            visitsDescriptor.fetchLimit = 2000
            visitsDescriptor.relationshipKeyPathsForPrefetching = [\.items]

            var categoryDescriptor = FetchDescriptor<CategoryDaySummary>(
                predicate: #Predicate<CategoryDaySummary> { summary in
                    summary.day >= start && summary.day < end
                }
            )
            categoryDescriptor.fetchLimit = 1000

            var paymentDescriptor = FetchDescriptor<Payment>(
                predicate: #Predicate<Payment> { payment in
                    payment.paidAt >= start && payment.paidAt < end
                }
            )
            paymentDescriptor.fetchLimit = 5000

            let visits: [Visit]
            do { visits = try bgContext.fetch(visitsDescriptor) }
            catch {
                Logger.insights.error("Distributions visits fetch failed: \(String(describing: error))")
                visits = []
            }
            let categories: [CategoryDaySummary]
            do { categories = try bgContext.fetch(categoryDescriptor) }
            catch {
                Logger.insights.error("Distributions category fetch failed: \(String(describing: error))")
                categories = []
            }
            let payments: [Payment]
            do { payments = try bgContext.fetch(paymentDescriptor) }
            catch {
                Logger.insights.error("Distributions payment fetch failed: \(String(describing: error))")
                payments = []
            }

            var serviceStats: [String: (count: Int, revenue: Decimal)] = [:]
            for visit in visits {
                for item in visit.items ?? [] {
                    serviceStats[item.name, default: (0, .zero)].count   += 1
                    serviceStats[item.name, default: (0, .zero)].revenue += item.lineTotal
                }
            }

            let services = serviceStats
                .map { name, stats in DistributionData(name: name, count: stats.count, revenue: stats.revenue) }
                .sorted { $0.revenue > $1.revenue }

            let categoryStats = SummaryUpdater.collapsedCategoryCounts(from: categories)
            let categoryDist = categoryStats
                .map { name, count in DistributionData(name: name, count: count) }
                .sorted { $0.count > $1.count }

            let paymentStats = Dictionary(grouping: payments, by: \.method)
                .map { method, rows in
                    PaymentMethodData(
                        method: method,
                        count: rows.count,
                        amount: rows.reduce(.zero) { $0 + $1.amount }
                    )
                }
                .sorted { $0.amount > $1.amount }

            return (services: services, categories: categoryDist, payments: paymentStats)
        }.value

        serviceDistribution  = result.services
        categoryDistribution = result.categories
        paymentMethodDistribution = result.payments
    }

    private func fetchClientInsights() async {
        let container = dataStore.container

        let result = await Task.detached(priority: .utility) { () -> ClientInsightsResult in
            let bgContext = ModelContext(container)

            var summaryDesc = FetchDescriptor<ClientInsightSummary>(
                sortBy: [SortDescriptor(\.totalSpent, order: .reverse)]
            )
            summaryDesc.fetchLimit = 5000
            let summaries: [ClientInsightSummary]
            do {
                summaries = try bgContext.fetch(summaryDesc)
            } catch {
                Logger.insights.error("Client insight summary fetch failed: \(String(describing: error))")
                summaries = []
            }

            if !summaries.isEmpty {
                let collapsed = Array(SummaryUpdater.collapsedClientInsightSummaries(from: summaries).values)
                let recurring = collapsed.filter(\.isRecurring).count
                let churn = collapsed.filter(\.isChurnRisk).count
                let oneTime = max(0, collapsed.count - recurring)
                let topRows = collapsed
                    .filter { $0.totalSpent > .zero }
                    .sorted { $0.totalSpent > $1.totalSpent }
                    .prefix(10)
                    .map {
                        TopClientData(
                            name: $0.clientName,
                            totalSpent: $0.totalSpent,
                            visitCount: $0.visitCount
                        )
                    }

                let series: [RetentionData]
                if recurring > 0 || oneTime > 0 {
                    series = [
                        RetentionData(label: "Recurring", value: Double(recurring)),
                        RetentionData(label: "One-time", value: Double(oneTime))
                    ]
                } else {
                    series = []
                }

                return ClientInsightsResult(
                    topClients: Array(topRows),
                    retentionRate: collapsed.isEmpty ? 0 : Double(recurring) / Double(collapsed.count),
                    churnRiskCount: churn,
                    retentionSeries: series
                )
            }

            var clientDesc = FetchDescriptor<Client>()
            clientDesc.relationshipKeyPathsForPrefetching = [\.pets]
            clientDesc.fetchLimit = 5000
            let clients: [Client]
            do { clients = try bgContext.fetch(clientDesc) }
            catch {
                Logger.insights.error("Client insights fetch failed: \(String(describing: error))")
                clients = []
            }

            var petDesc = FetchDescriptor<Pet>()
            petDesc.relationshipKeyPathsForPrefetching = [\.visits]
            petDesc.fetchLimit = 10000
            do {
                _ = try bgContext.fetch(petDesc)
            } catch {
                Logger.insights.error("Pet prefetch failed: \(String(describing: error))")
            }

            var recurring = 0
            var churn = 0
            var clientRows: [TopClientData] = []

            for client in clients {
                let visits = (client.pets ?? []).flatMap { $0.visits ?? [] }.filter { $0.isCompleted }
                let spent  = visits.reduce(Decimal.zero) { $0 + $1.total }

                if visits.count > 1 {
                    recurring += 1
                }
                if (client.pets ?? []).contains(where: { $0.isOverdue }) {
                    churn += 1
                }

                if spent > .zero {
                    clientRows.append(TopClientData(name: client.fullName, totalSpent: spent, visitCount: visits.count))
                }
            }

            let rows = Array(clientRows.sorted { $0.totalSpent > $1.totalSpent }.prefix(10))

            guard !clients.isEmpty else {
                return ClientInsightsResult(topClients: rows, retentionRate: 0, churnRiskCount: 0, retentionSeries: [])
            }

            let oneTime = clients.count - recurring
            let series: [RetentionData]
            if recurring > 0 || oneTime > 0 {
                series = [
                    RetentionData(label: "Recurring", value: Double(recurring)),
                    RetentionData(label: "One-time",  value: Double(oneTime))
                ]
            } else {
                series = []
            }

            return ClientInsightsResult(
                topClients: rows,
                retentionRate: Double(recurring) / Double(clients.count),
                churnRiskCount: churn,
                retentionSeries: series
            )
        }.value

        topClients = result.topClients
        retentionRate = result.retentionRate
        churnRiskCount = result.churnRiskCount
        retentionSeries = result.retentionSeries
    }

    private func fetchMonthlyGrowth() async {
        let cal = Calendar.current
        let now = Date()
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMM"

        guard let earliestMonthDate = cal.date(byAdding: .month, value: -5, to: now),
              let rangeStart = cal.date(from: cal.dateComponents([.year, .month], from: earliestMonthDate)),
              let rangeEnd   = cal.date(byAdding: .month, value: 1,
                                        to: cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now)
        else { return }

        let container = dataStore.container
        let rows = await Task.detached(priority: .utility) { () -> [MonthlyGrowthData] in
            let bgContext = ModelContext(container)
            var descriptor = FetchDescriptor<DaySummary>(
                predicate: #Predicate<DaySummary> { summary in
                    summary.day >= rangeStart && summary.day < rangeEnd
                }
            )
            // 6 months × ~31 days = ~186 rows max. Cap defensively.
            descriptor.fetchLimit = 1000
            let summaries: [DaySummary]
            do { summaries = try bgContext.fetch(descriptor) }
            catch {
                Logger.insights.error("Monthly growth fetch failed: \(String(describing: error))")
                summaries = []
            }
            let collapsed = SummaryUpdater.collapsedDayAggregates(from: summaries)

            var buckets: [(start: Date, label: String, revenue: Decimal, count: Int)] = []
            for i in (0..<6).reversed() {
                guard let monthDate  = cal.date(byAdding: .month, value: -i, to: now),
                      let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: monthDate))
                else { continue }
                buckets.append((start: monthStart,
                                label: monthFormatter.string(from: monthStart),
                                revenue: .zero, count: 0))
            }

            for summary in collapsed.values {
                let ms = cal.date(from: cal.dateComponents([.year, .month], from: summary.day))
                guard let ms, let idx = buckets.firstIndex(where: { $0.start == ms }) else { continue }
                buckets[idx].revenue += summary.revenue
                buckets[idx].count   += summary.visitCount
            }

            return buckets.map {
                MonthlyGrowthData(month: $0.label, revenue: $0.revenue, visitCount: $0.count)
            }
        }.value

        monthlyGrowth = rows
    }
}

private extension Logger {
    static let insights = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "Insights")
}
