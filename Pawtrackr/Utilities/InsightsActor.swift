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

    struct ActionableInsightsResult: Sendable {
        let revenueDrilldown: [InsightsViewModel.RevenueVisitData]
        let serviceProfitability: [InsightsViewModel.ServiceProfitabilityData]
        let lapsedClients: [InsightsViewModel.LapsedClientData]
        let forecast: InsightsViewModel.ForecastData?
        let comparisons: [InsightsViewModel.ComparisonData]
        let dataQualityIssues: [InsightsViewModel.DataQualityIssue]
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
                InsightsViewModel.RetentionData(
                    label: NSLocalizedString("insights.retention.recurring", value: "Recurring", comment: ""),
                    value: Double(recurring)
                ),
                InsightsViewModel.RetentionData(
                    label: NSLocalizedString("insights.retention.one_time", value: "One-time", comment: ""),
                    value: Double(oneTime)
                )
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

    func fetchActionableInsights(periodDays: Int) async throws -> ActionableInsightsResult {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86_400)
        let normalizedPeriod = max(1, min(periodDays, 365))
        let currentStart = cal.date(byAdding: .day, value: -(normalizedPeriod - 1), to: today) ?? today
        let priorStart = cal.date(byAdding: .day, value: -normalizedPeriod, to: currentStart) ?? currentStart

        var visitDescriptor = FetchDescriptor<Visit>(
            predicate: #Predicate<Visit> { visit in
                if let endedAt = visit.endedAt {
                    endedAt >= priorStart && endedAt < tomorrow
                } else {
                    false
                }
            }
        )
        visitDescriptor.fetchLimit = 10_000
        visitDescriptor.relationshipKeyPathsForPrefetching = [\.items]
        let visits = try modelContext.fetch(visitDescriptor)

        let currentVisits = visits
            .filter { ($0.endedAt ?? $0.startedAt) >= currentStart && ($0.endedAt ?? $0.startedAt) < tomorrow }
            .sorted { ($0.endedAt ?? $0.startedAt) > ($1.endedAt ?? $1.startedAt) }

        let priorVisits = visits
            .filter { ($0.endedAt ?? $0.startedAt) >= priorStart && ($0.endedAt ?? $0.startedAt) < currentStart }

        let revenueRows = currentVisits.prefix(50).map { visit in
            InsightsViewModel.RevenueVisitData(
                date: visit.endedAt ?? visit.startedAt,
                petName: visit.pet?.name ?? "Unknown pet",
                clientName: visit.pet?.owner?.fullName ?? "Unknown client",
                serviceSummary: Self.serviceSummary(for: visit),
                total: visit.total,
                paymentMethod: visit.payment?.method.displayName ?? "Unpaid"
            )
        }

        let serviceProfitability = Self.serviceProfitability(currentVisits: currentVisits, priorVisits: priorVisits)
        let lapsedClients = try fetchLapsedClients(calendar: cal, today: today)
        let daySummaries = try fetchDayAggregates(startingDaysBack: 395, calendar: cal, end: tomorrow)
        let forecast = Self.forecast(from: daySummaries, calendar: cal, today: today, end: tomorrow)
        let comparisons = Self.comparisons(from: daySummaries, calendar: cal, today: today, end: tomorrow)
        let quality = try fetchDataQualityIssues(calendar: cal, today: today, end: tomorrow)

        return ActionableInsightsResult(
            revenueDrilldown: revenueRows,
            serviceProfitability: serviceProfitability,
            lapsedClients: lapsedClients,
            forecast: forecast,
            comparisons: comparisons,
            dataQualityIssues: quality
        )
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
            InsightsViewModel.RetentionData(
                label: NSLocalizedString("insights.retention.recurring", value: "Recurring", comment: ""),
                value: Double(recurring)
            ),
            InsightsViewModel.RetentionData(
                label: NSLocalizedString("insights.retention.one_time", value: "One-time", comment: ""),
                value: Double(oneTime)
            )
        ]
        
        return ClientInsightsResult(
            topClients: rows,
            retentionRate: clients.isEmpty ? 0 : Double(recurring) / Double(clients.count),
            churnRiskCount: churn,
            retentionSeries: series
        )
    }

    private func fetchLapsedClients(calendar cal: Calendar, today: Date) throws -> [InsightsViewModel.LapsedClientData] {
        var summaryDesc = FetchDescriptor<ClientInsightSummary>()
        summaryDesc.fetchLimit = 5_000
        let collapsedSummaries = SummaryUpdater.collapsedClientInsightSummaries(from: try modelContext.fetch(summaryDesc))

        var clientDesc = FetchDescriptor<Client>(sortBy: [SortDescriptor(\.lastVisitDate)])
        clientDesc.relationshipKeyPathsForPrefetching = [\.pets]
        clientDesc.fetchLimit = 5_000
        let clients = try modelContext.fetch(clientDesc)
        let clientsByUUID = Dictionary(uniqueKeysWithValues: clients.map { ($0.uuid, $0) })

        if !collapsedSummaries.isEmpty {
            return collapsedSummaries.values.compactMap { summary -> InsightsViewModel.LapsedClientData? in
                guard let lastVisit = summary.lastVisitAt,
                      let client = clientsByUUID[summary.clientUUID]
                else { return nil }

                return makeLapsedClientRow(
                    client: client,
                    fallbackName: summary.clientName,
                    totalSpent: summary.totalSpent,
                    lastVisit: lastVisit,
                    calendar: cal,
                    today: today
                )
            }
            .sorted {
                if $0.daysSinceLastVisit == $1.daysSinceLastVisit {
                    return $0.totalSpent > $1.totalSpent
                }
                return $0.daysSinceLastVisit > $1.daysSinceLastVisit
            }
            .prefix(8)
            .map { $0 }
        }

        return clients.compactMap { client in
            guard let lastVisit = client.lastVisitDate else { return nil }
            return makeLapsedClientRow(
                client: client,
                fallbackName: client.fullName,
                totalSpent: .zero,
                lastVisit: lastVisit,
                calendar: cal,
                today: today
            )
        }
        .sorted { $0.daysSinceLastVisit > $1.daysSinceLastVisit }
        .prefix(8)
        .map { $0 }
    }

    private func makeLapsedClientRow(
        client: Client,
        fallbackName: String,
        totalSpent: Decimal,
        lastVisit: Date,
        calendar cal: Calendar,
        today: Date
    ) -> InsightsViewModel.LapsedClientData? {
            let daysSince = cal.dateComponents([.day], from: cal.startOfDay(for: lastVisit), to: today).day ?? 0
            guard daysSince >= 90 else { return nil }

            let pets = client.pets ?? []
            let petNames = pets.map(\.name).filter { !$0.isEmpty }.joined(separator: ", ")
            let primaryPetUUID = pets.first?.uuid
            let firstPetName = pets.first?.name ?? NSLocalizedString("insights.lapsed.your_pet", value: "your pet", comment: "")
            let clientName = client.firstName.isEmpty ? client.fullName : client.firstName
            let message = String(
                format: NSLocalizedString(
                    "insights.lapsed.suggested_message_fmt",
                    value: "Hi %@, it has been a while since %@'s last visit. Would you like to schedule a grooming appointment?",
                    comment: ""
                ),
                clientName,
                firstPetName
            )

            return InsightsViewModel.LapsedClientData(
                id: client.uuid,
                name: client.fullName.isEmpty
                    ? (fallbackName.isEmpty
                        ? NSLocalizedString("insights.lapsed.unnamed_client", value: "Unnamed client", comment: "")
                        : fallbackName)
                    : client.fullName,
                petNames: petNames.isEmpty ? NSLocalizedString("insights.lapsed.no_pets_listed", value: "No pets listed", comment: "") : petNames,
                daysSinceLastVisit: daysSince,
                totalSpent: totalSpent,
                phone: client.phone,
                primaryPetUUID: primaryPetUUID,
                suggestedMessage: message
            )
    }

    private func fetchDayAggregates(startingDaysBack daysBack: Int, calendar cal: Calendar, end: Date) throws -> [SummaryUpdater.DayAggregate] {
        let start = cal.date(byAdding: .day, value: -daysBack, to: end) ?? end
        let descriptor = FetchDescriptor<DaySummary>(
            predicate: #Predicate<DaySummary> { $0.day >= start && $0.day < end }
        )
        let summaries = try modelContext.fetch(descriptor)
        return Array(SummaryUpdater.collapsedDayAggregates(from: summaries).values)
    }

    private func fetchDataQualityIssues(calendar cal: Calendar, today: Date, end: Date) throws -> [InsightsViewModel.DataQualityIssue] {
        let staleActiveCutoff = cal.date(byAdding: .day, value: -1, to: .now) ?? .now
        let qualityStart = cal.date(byAdding: .day, value: -365, to: today) ?? today

        let activeDescriptor = FetchDescriptor<Visit>(
            predicate: #Predicate<Visit> { visit in
                visit.endedAt == nil && visit.startedAt < staleActiveCutoff
            }
        )
        let staleActiveCount = try modelContext.fetchCount(activeDescriptor)

        var completedDescriptor = FetchDescriptor<Visit>(
            predicate: #Predicate<Visit> { visit in
                if let endedAt = visit.endedAt {
                    endedAt >= qualityStart && endedAt < end
                } else {
                    false
                }
            }
        )
        completedDescriptor.fetchLimit = 10_000
        let completed = try modelContext.fetch(completedDescriptor)

        let missingPayment = completed.filter { $0.payment == nil }.count
        let zeroRevenue = completed.filter { $0.total <= .zero }.count

        let missingReference = completed.filter { visit in
            guard let payment = visit.payment, payment.method.requiresExternalReference else { return false }
            return (payment.externalReference ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count

        var clientDescriptor = FetchDescriptor<Client>()
        clientDescriptor.fetchLimit = 10_000
        let clients = try modelContext.fetch(clientDescriptor)
        let missingContact = clients.filter {
            ($0.phone ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            ($0.email ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count

        var issues: [InsightsViewModel.DataQualityIssue] = []
        if staleActiveCount > 0 {
            issues.append(.init(
                title: NSLocalizedString("insights.data_quality.stale_active_title", value: "Stale active visits", comment: ""),
                detail: NSLocalizedString("insights.data_quality.stale_active_detail", value: "Visits checked in for more than 24 hours can distort active workload.", comment: ""),
                count: staleActiveCount,
                severity: .critical
            ))
        }
        if missingPayment > 0 {
            issues.append(.init(
                title: NSLocalizedString("insights.data_quality.missing_payment_title", value: "Completed visits without payment", comment: ""),
                detail: NSLocalizedString("insights.data_quality.missing_payment_detail", value: "These visits are finished but do not have a payment record.", comment: ""),
                count: missingPayment,
                severity: .warning
            ))
        }
        if zeroRevenue > 0 {
            issues.append(.init(
                title: NSLocalizedString("insights.data_quality.zero_revenue_title", value: "Zero-dollar completed visits", comment: ""),
                detail: NSLocalizedString("insights.data_quality.zero_revenue_detail", value: "Review comped or incomplete checkouts before relying on revenue totals.", comment: ""),
                count: zeroRevenue,
                severity: .warning
            ))
        }
        if missingReference > 0 {
            issues.append(.init(
                title: NSLocalizedString("insights.data_quality.missing_reference_title", value: "Card/Zelle references missing", comment: ""),
                detail: NSLocalizedString("insights.data_quality.missing_reference_detail", value: "Payment references help reconcile deposits and charge disputes.", comment: ""),
                count: missingReference,
                severity: .info
            ))
        }
        if missingContact > 0 {
            issues.append(.init(
                title: NSLocalizedString("insights.data_quality.missing_contact_title", value: "Clients missing contact info", comment: ""),
                detail: NSLocalizedString("insights.data_quality.missing_contact_detail", value: "Add phone or email so recall campaigns can reach every client.", comment: ""),
                count: missingContact,
                severity: .info
            ))
        }

        return issues
    }

    private static func serviceSummary(for visit: Visit) -> String {
        let names = (visit.items ?? []).map(\.displayName).filter { !$0.isEmpty }
        if names.isEmpty { return "No services listed" }
        if names.count <= 2 { return names.joined(separator: ", ") }
        return "\(names.prefix(2).joined(separator: ", ")) +\(names.count - 2)"
    }

    private static func serviceProfitability(currentVisits: [Visit], priorVisits: [Visit]) -> [InsightsViewModel.ServiceProfitabilityData] {
        typealias ServiceStats = (category: String, count: Int, revenue: Decimal)
        var current: [String: ServiceStats] = [:]
        var prior: [String: ServiceStats] = [:]

        func add(_ item: VisitItem, to stats: inout [String: ServiceStats]) {
            let category = item.serviceCategoryRaw.flatMap(Service.Category.init(rawValue:))?.rawValue ?? "Uncategorized"
            let existing = stats[item.name] ?? (category, 0, .zero)
            stats[item.name] = (existing.category, existing.count + item.quantity, existing.revenue + item.lineTotal)
        }

        for visit in currentVisits {
            for item in visit.items ?? [] {
                add(item, to: &current)
            }
        }

        for visit in priorVisits {
            for item in visit.items ?? [] {
                add(item, to: &prior)
            }
        }

        return current.map { name, stats in
            let priorRevenue = prior[name]?.revenue ?? .zero
            let trend: Double
            if priorRevenue > .zero {
                trend = (((stats.revenue - priorRevenue) / priorRevenue) as NSDecimalNumber).doubleValue
            } else {
                trend = stats.revenue > .zero ? 1 : 0
            }

            return InsightsViewModel.ServiceProfitabilityData(
                name: name,
                category: stats.category,
                count: stats.count,
                revenue: stats.revenue,
                averageTicket: stats.count > 0 ? (stats.revenue / Decimal(stats.count)).roundedMoney() : .zero,
                trendPercent: trend
            )
        }
        .sorted { $0.revenue > $1.revenue }
        .prefix(10)
        .map { $0 }
    }

    private static func forecast(
        from summaries: [SummaryUpdater.DayAggregate],
        calendar cal: Calendar,
        today: Date,
        end: Date
    ) -> InsightsViewModel.ForecastData? {
        let start = cal.date(byAdding: .day, value: -89, to: today) ?? today
        let rows = summaries.filter { $0.day >= start && $0.day < end }
        let visits = rows.reduce(0) { $0 + $1.visitCount }
        guard visits > 0 else { return nil }

        let revenue = rows.reduce(Decimal.zero) { $0 + $1.revenue }
        let dayCount = max(1, cal.dateComponents([.day], from: start, to: end).day ?? 90)
        let dailyAverage = (revenue / Decimal(dayCount)).roundedMoney()
        let projectedVisits = Int((Double(visits) / Double(dayCount) * 30.0).rounded())

        let confidence: String
        switch visits {
        case 50...:
            confidence = NSLocalizedString("insights.forecast.confidence.high", value: "High confidence", comment: "")
        case 15..<50:
            confidence = NSLocalizedString("insights.forecast.confidence.medium", value: "Medium confidence", comment: "")
        default:
            confidence = NSLocalizedString("insights.forecast.confidence.low", value: "Low confidence", comment: "")
        }

        return InsightsViewModel.ForecastData(
            projectedRevenue: (dailyAverage * Decimal(30)).roundedMoney(),
            projectedVisits: max(1, projectedVisits),
            dailyAverageRevenue: dailyAverage,
            confidenceLabel: confidence,
            basis: String(
                format: NSLocalizedString("insights.forecast.basis_fmt", value: "Based on %d visits across the last %d days", comment: ""),
                visits,
                dayCount
            )
        )
    }

    private static func comparisons(
        from summaries: [SummaryUpdater.DayAggregate],
        calendar cal: Calendar,
        today: Date,
        end: Date
    ) -> [InsightsViewModel.ComparisonData] {
        func totals(start: Date, end: Date) -> (revenue: Decimal, visits: Int) {
            let rows = summaries.filter { $0.day >= start && $0.day < end }
            return (
                rows.reduce(.zero) { $0 + $1.revenue },
                rows.reduce(0) { $0 + $1.visitCount }
            )
        }

        func comparison(label: String, currentStart: Date, currentEnd: Date, priorStart: Date, priorEnd: Date) -> InsightsViewModel.ComparisonData {
            let current = totals(start: currentStart, end: currentEnd)
            let prior = totals(start: priorStart, end: priorEnd)
            return InsightsViewModel.ComparisonData(
                label: label,
                currentRevenue: current.revenue,
                previousRevenue: prior.revenue,
                currentVisits: current.visits,
                previousVisits: prior.visits
            )
        }

        let currentWeekStart = cal.date(byAdding: .day, value: -6, to: today) ?? today
        let priorWeekStart = cal.date(byAdding: .day, value: -7, to: currentWeekStart) ?? currentWeekStart
        let currentMonthStart = cal.date(byAdding: .day, value: -29, to: today) ?? today
        let priorMonthStart = cal.date(byAdding: .day, value: -30, to: currentMonthStart) ?? currentMonthStart

        var result: [InsightsViewModel.ComparisonData] = [
            comparison(
                label: NSLocalizedString("insights.comparison.7d_prior", value: "7 days vs prior 7", comment: ""),
                currentStart: currentWeekStart,
                currentEnd: end,
                priorStart: priorWeekStart,
                priorEnd: currentWeekStart
            ),
            comparison(
                label: NSLocalizedString("insights.comparison.30d_prior", value: "30 days vs prior 30", comment: ""),
                currentStart: currentMonthStart,
                currentEnd: end,
                priorStart: priorMonthStart,
                priorEnd: currentMonthStart
            )
        ]

        if let lastYearStart = cal.date(byAdding: .year, value: -1, to: currentMonthStart),
           let lastYearEnd = cal.date(byAdding: .year, value: -1, to: end) {
            let prior = totals(start: lastYearStart, end: lastYearEnd)
            if prior.visits > 0 || prior.revenue > .zero {
                let current = totals(start: currentMonthStart, end: end)
                result.append(
                    InsightsViewModel.ComparisonData(
                        label: NSLocalizedString("insights.comparison.30d_last_year", value: "30 days vs last year", comment: ""),
                        currentRevenue: current.revenue,
                        previousRevenue: prior.revenue,
                        currentVisits: current.visits,
                        previousVisits: prior.visits
                    )
                )
            }
        }

        return result
    }
}
