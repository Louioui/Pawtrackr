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

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Public

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer {
            isRefreshing = false
            hasLoadedOnce = true
        }

        async let rev:       () = fetchRevenue()
        async let dist:      () = fetchDistributions()
        async let top:       () = fetchTopClients()
        async let growth:    () = fetchMonthlyGrowth()
        async let retention: () = fetchRetentionMetrics()

        _ = await [rev, dist, top, growth, retention]
    }

    func refreshRevenue() async {
        await fetchRevenue()
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
        let newClientsCount = (try? modelContext.fetchCount(descriptor)) ?? 0

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
        let container  = modelContext.container
        let periodDays = revenuePeriodDays
        let cal        = Calendar.current
        let end        = cal.startOfDay(for: .now)
        guard let start = cal.date(byAdding: .day, value: -(periodDays - 1), to: end) else { return }

        let result = await Task.detached(priority: .userInitiated) {
            () -> (points: [(Date, Decimal)], totalVisits: Int) in
            let bgContext = ModelContext(container)
            let descriptor = FetchDescriptor<DaySummary>(
                predicate: #Predicate<DaySummary> { summary in
                    summary.day >= start && summary.day <= end
                }
            )
            let summaries   = (try? bgContext.fetch(descriptor)) ?? []
            let points      = summaries.map { ($0.day, $0.revenue) }.sorted { $0.0 < $1.0 }
            let totalVisits = summaries.reduce(0) { $0 + $1.visitCount }
            return (points: points, totalVisits: totalVisits)
        }.value

        revenueSeries       = result.points.map { RevenueData(date: $0.0, amount: $0.1) }
        totalRevenue        = result.points.reduce(.zero) { $0 + $1.1 }
        totalVisitsInPeriod = result.totalVisits
        averageVisitValue   = result.totalVisits > 0
            ? totalRevenue / Decimal(result.totalVisits)
            : .zero
    }

    private func fetchDistributions() async {
        let container = modelContext.container
        let cal   = Calendar.current
        let end   = cal.startOfDay(for: .now).addingTimeInterval(86400)
        let start = cal.date(byAdding: .day, value: -30, to: end) ?? end

        let result = await Task.detached(priority: .userInitiated) {
            () -> (services: [DistributionData], categories: [DistributionData], payments: [PaymentMethodData]) in

            let bgContext = ModelContext(container)

            var visitsDescriptor = FetchDescriptor<Visit>(
                predicate: #Predicate<Visit> { $0.endedAt != nil },
                sortBy: [SortDescriptor(\.endedAt, order: .reverse)]
            )
            visitsDescriptor.fetchLimit = 2000
            visitsDescriptor.relationshipKeyPathsForPrefetching = [\.items]

            let categoryDescriptor = FetchDescriptor<CategoryDaySummary>(
                predicate: #Predicate<CategoryDaySummary> { summary in
                    summary.day >= start && summary.day < end
                }
            )

            let paymentDescriptor = FetchDescriptor<Payment>(
                predicate: #Predicate<Payment> { payment in
                    payment.paidAt >= start && payment.paidAt < end
                }
            )

            let visits = ((try? bgContext.fetch(visitsDescriptor)) ?? []).filter { visit in
                guard let endedAt = visit.endedAt else { return false }
                return endedAt >= start && endedAt < end
            }
            let categories = (try? bgContext.fetch(categoryDescriptor)) ?? []
            let payments = (try? bgContext.fetch(paymentDescriptor)) ?? []

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

            let categoryStats = categories.reduce(into: [String: Int]()) { acc, s in
                acc[s.categoryRaw, default: 0] += s.count
            }
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

    private func fetchTopClients() async {
        let container = modelContext.container

        let rows = await Task.detached(priority: .userInitiated) { () -> [TopClientData] in
            let bgContext = ModelContext(container)

            var clientDesc = FetchDescriptor<Client>()
            clientDesc.relationshipKeyPathsForPrefetching = [\.pets]
            let clients = (try? bgContext.fetch(clientDesc)) ?? []

            var petDesc = FetchDescriptor<Pet>()
            petDesc.relationshipKeyPathsForPrefetching = [\.visits]
            _ = try? bgContext.fetch(petDesc)

            return clients.map { client in
                let visits = (client.pets ?? []).flatMap { $0.visits ?? [] }.filter { $0.isCompleted }
                let spent  = visits.reduce(Decimal.zero) { $0 + $1.total }
                return TopClientData(name: client.fullName, totalSpent: spent, visitCount: visits.count)
            }
            .filter  { $0.totalSpent > 0 }
            .sorted  { $0.totalSpent > $1.totalSpent }
            .prefix(10)
            .map     { $0 }
        }.value

        topClients = rows
    }

    private func fetchRetentionMetrics() async {
        let container = modelContext.container

        let result = await Task.detached(priority: .userInitiated) {
            () -> (rate: Double, churn: Int, recurring: Int, oneTime: Int)? in

            let bgCtx = ModelContext(container)

            var clientDesc = FetchDescriptor<Client>()
            clientDesc.relationshipKeyPathsForPrefetching = [\.pets]
            guard let allClients = try? bgCtx.fetch(clientDesc),
                  !allClients.isEmpty else { return nil }

            var petDesc = FetchDescriptor<Pet>()
            petDesc.relationshipKeyPathsForPrefetching = [\.visits]
            _ = try? bgCtx.fetch(petDesc)

            var recurring = 0
            var churn     = 0
            for client in allClients {
                var completedCount = 0
                outer: for pet in client.pets ?? [] {
                    for visit in pet.visits ?? [] where visit.isCompleted {
                        completedCount += 1
                        if completedCount > 1 { break outer }
                    }
                }
                if completedCount > 1 { recurring += 1 }
                if (client.pets ?? []).contains(where: { $0.isOverdue }) { churn += 1 }
            }

            let rate = Double(recurring) / Double(allClients.count)
            return (rate: rate, churn: churn,
                    recurring: recurring, oneTime: allClients.count - recurring)
        }.value

        guard let result else { return }
        retentionRate  = result.rate
        churnRiskCount = result.churn

        // Guard against both-zero state which produces an invisible chart
        guard result.recurring > 0 || result.oneTime > 0 else {
            retentionSeries = []
            return
        }
        retentionSeries = [
            RetentionData(label: "Recurring", value: Double(result.recurring)),
            RetentionData(label: "One-time",  value: Double(result.oneTime))
        ]
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

        let container = modelContext.container
        let rows = await Task.detached(priority: .userInitiated) { () -> [MonthlyGrowthData] in
            let bgContext = ModelContext(container)
            let descriptor = FetchDescriptor<DaySummary>(
                predicate: #Predicate<DaySummary> { summary in
                    summary.day >= rangeStart && summary.day < rangeEnd
                }
            )
            let summaries = (try? bgContext.fetch(descriptor)) ?? []

            var buckets: [(start: Date, label: String, revenue: Decimal, count: Int)] = []
            for i in (0..<6).reversed() {
                guard let monthDate  = cal.date(byAdding: .month, value: -i, to: now),
                      let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: monthDate))
                else { continue }
                buckets.append((start: monthStart,
                                label: monthFormatter.string(from: monthStart),
                                revenue: .zero, count: 0))
            }

            for summary in summaries {
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
