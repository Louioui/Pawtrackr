//
//  InsightsActor.swift
//  Pawtrackr
//
//  Dedicated background actor for heavy analytics, aggregation, and pre-fetching.
//  Ensures Insights logic never blocks the MainActor and enables anticipatory loading.
//

import Foundation
import SwiftData
import OSLog

private let insightsLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "InsightsActor")

@ModelActor
final actor InsightsActor {
    
    struct RevenueResult: Sendable {
        let series: [InsightsViewModel.RevenueData]
        let totalRevenue: Decimal
        let totalVisits: Int
        let averageVisitValue: Decimal
    }
    
    struct DistributionResult: Sendable {
        let services: [InsightsViewModel.DistributionData]
        let categories: [InsightsViewModel.DistributionData]
        let payments: [InsightsViewModel.PaymentMethodData]
    }
    
    struct ClientInsightsResult: Sendable {
        let topClients: [InsightsViewModel.TopClientData]
        let retentionRate: Double
        let churnRiskCount: Int
        let retentionSeries: [InsightsViewModel.RetentionData]
    }
    
    // MARK: - Core Analytics
    
    func fetchRevenue(periodDays: Int) async throws -> RevenueResult {
        let cal = Calendar.current
        let end = cal.startOfDay(for: .now)
        guard let start = cal.date(byAdding: .day, value: -(periodDays - 1), to: end) else {
            throw AppError.validation(.custom(message: "Invalid date range"))
        }
        
        var descriptor = FetchDescriptor<DaySummary>(
            predicate: #Predicate<DaySummary> { summary in
                summary.day >= start && summary.day <= end
            }
        )
        descriptor.fetchLimit = 500
        
        let summaries = try modelContext.fetch(descriptor)
        let aggregates = SummaryUpdater.collapsedDayAggregates(from: summaries).values.sorted { $0.day < $1.day }
        
        let totalVisits = aggregates.reduce(0) { $0 + $1.visitCount }
        let totalRevenue = aggregates.reduce(Decimal.zero) { $0 + $1.revenue }
        
        return RevenueResult(
            series: aggregates.map { InsightsViewModel.RevenueData(date: $0.day, amount: $0.revenue) },
            totalRevenue: totalRevenue,
            totalVisits: totalVisits,
            averageVisitValue: totalVisits > 0 ? totalRevenue / Decimal(totalVisits) : .zero
        )
    }
    
    func fetchDistributions() async throws -> DistributionResult {
        let cal = Calendar.current
        let end = cal.startOfDay(for: .now).addingTimeInterval(86400)
        let start = cal.date(byAdding: .day, value: -30, to: end) ?? end
        
        // 1. Fetch Visits with pre-fetching
        var visitsDescriptor = FetchDescriptor<Visit>(
            predicate: #Predicate<Visit> { visit in
                if let endedAt = visit.endedAt {
                    endedAt >= start && endedAt < end
                } else {
                    false
                }
            }
        )
        visitsDescriptor.relationshipKeyPathsForPrefetching = [\.items]
        let visits = try modelContext.fetch(visitsDescriptor)
        
        // 2. Fetch Category Summaries
        let categoryDescriptor = FetchDescriptor<CategoryDaySummary>(
            predicate: #Predicate<CategoryDaySummary> { $0.day >= start && $0.day < end }
        )
        let categories = try modelContext.fetch(categoryDescriptor)
        
        // 3. Fetch Payments
        let paymentDescriptor = FetchDescriptor<Payment>(
            predicate: #Predicate<Payment> { $0.paidAt >= start && $0.paidAt < end }
        )
        let payments = try modelContext.fetch(paymentDescriptor)
        
        // Aggregate Services
        var serviceStats: [String: (count: Int, revenue: Decimal)] = [:]
        for visit in visits {
            for item in visit.items ?? [] {
                serviceStats[item.name, default: (0, .zero)].count   += 1
                serviceStats[item.name, default: (0, .zero)].revenue += item.lineTotal
            }
        }
        
        let services = serviceStats
            .map { InsightsViewModel.DistributionData(name: $0.key, count: $0.value.count, revenue: $0.value.revenue) }
            .sorted { $0.revenue > $1.revenue }
        
        let categoryDist = SummaryUpdater.collapsedCategoryCounts(from: categories)
            .map { InsightsViewModel.DistributionData(name: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
        
        let paymentDist = Dictionary(grouping: payments, by: \.method)
            .map { method, rows in
                InsightsViewModel.PaymentMethodData(
                    method: method,
                    count: rows.count,
                    amount: rows.reduce(.zero) { $0 + $1.amount }
                )
            }
            .sorted { $0.amount > $1.amount }
            
        return DistributionResult(services: services, categories: categoryDist, payments: paymentDist)
    }
    
    func fetchClientInsights() async throws -> ClientInsightsResult {
        var summaryDesc = FetchDescriptor<ClientInsightSummary>(
            sortBy: [SortDescriptor(\.totalSpent, order: .reverse)]
        )
        summaryDesc.fetchLimit = 5000
        let summaries = try modelContext.fetch(summaryDesc)
        
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
                    InsightsViewModel.TopClientData(
                        name: $0.clientName,
                        totalSpent: $0.totalSpent,
                        visitCount: $0.visitCount
                    )
                }
            
            let series = [
                InsightsViewModel.RetentionData(label: "Recurring", value: Double(recurring)),
                InsightsViewModel.RetentionData(label: "One-time", value: Double(oneTime))
            ]
            
            return ClientInsightsResult(
                topClients: Array(topRows),
                retentionRate: collapsed.isEmpty ? 0 : Double(recurring) / Double(collapsed.count),
                churnRiskCount: churn,
                retentionSeries: series
            )
        }
        
        // Fallback to legacy calculation if no summaries
        return try await calculateLegacyClientInsights()
    }
    
    func fetchMonthlyGrowth() async throws -> [InsightsViewModel.MonthlyGrowthData] {
        let cal = Calendar.current
        let now = Date()
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMM"

        guard let earliestMonthDate = cal.date(byAdding: .month, value: -5, to: now),
              let rangeStart = cal.date(from: cal.dateComponents([.year, .month], from: earliestMonthDate)),
              let rangeEnd   = cal.date(byAdding: .month, value: 1, to: cal.startOfDay(for: now))
        else { return [] }

        let descriptor = FetchDescriptor<DaySummary>(
            predicate: #Predicate<DaySummary> { $0.day >= rangeStart && $0.day < rangeEnd }
        )
        let summaries = try modelContext.fetch(descriptor)
        let collapsed = SummaryUpdater.collapsedDayAggregates(from: summaries)

        var buckets: [(start: Date, label: String, revenue: Decimal, count: Int)] = []
        for i in (0..<6).reversed() {
            guard let monthDate  = cal.date(byAdding: .month, value: -i, to: now),
                  let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: monthDate))
            else { continue }
            buckets.append((start: monthStart, label: monthFormatter.string(from: monthStart), revenue: .zero, count: 0))
        }

        for summary in collapsed.values {
            let ms = cal.date(from: cal.dateComponents([.year, .month], from: summary.day))
            guard let ms, let idx = buckets.firstIndex(where: { $0.start == ms }) else { continue }
            buckets[idx].revenue += summary.revenue
            buckets[idx].count   += summary.visitCount
        }

        return buckets.map {
            InsightsViewModel.MonthlyGrowthData(month: $0.label, revenue: $0.revenue, visitCount: $0.count)
        }
    }
    
    // MARK: - Private Helpers
    
    private func calculateLegacyClientInsights() async throws -> ClientInsightsResult {
        var clientDesc = FetchDescriptor<Client>()
        clientDesc.relationshipKeyPathsForPrefetching = [\.pets]
        clientDesc.fetchLimit = 5000
        let clients = try modelContext.fetch(clientDesc)
        
        var recurring = 0
        var churn = 0
        var clientRows: [InsightsViewModel.TopClientData] = []

        for client in clients {
            let visits = (client.pets ?? []).flatMap { $0.visits ?? [] }.filter { $0.isCompleted }
            let spent  = visits.reduce(Decimal.zero) { $0 + $1.total }

            if visits.count > 1 { recurring += 1 }
            if (client.pets ?? []).contains(where: { $0.isOverdue }) { churn += 1 }

            if spent > .zero {
                clientRows.append(InsightsViewModel.TopClientData(name: client.fullName, totalSpent: spent, visitCount: visits.count))
            }
        }

        let rows = Array(clientRows.sorted { $0.totalSpent > $1.totalSpent }.prefix(10))
        let oneTime = clients.count - recurring
        let series = [
            InsightsViewModel.RetentionData(label: "Recurring", value: Double(recurring)),
            InsightsViewModel.RetentionData(label: "One-time",  value: Double(oneTime))
        ]
        
        return ClientInsightsResult(
            topClients: rows,
            retentionRate: clients.isEmpty ? 0 : Double(recurring) / Double(clients.count),
            churnRiskCount: churn,
            retentionSeries: series
        )
    }
}
