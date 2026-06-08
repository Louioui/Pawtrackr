//
//  DashboardRepository.swift
//  Pawtrackr
//

import Foundation
import SwiftData
import OSLog

private let dashboardRepoLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "DashboardRepository")

struct DashboardKPI: Sendable {
    var inProgressCount: Int = 0
    var revenueToday: Decimal = .zero
    var revenueYesterday: Decimal = .zero
    var completedToday: Int = 0
}

protocol DashboardRepositoryProtocol: Sendable {
    func fetchKPIs() async throws -> DashboardKPI
    func fetchActiveVisits() async throws -> [PersistentIdentifier]
    func fetchRecentClients(limit: Int) async throws -> [PersistentIdentifier]
    func fetchOverduePets(limit: Int) async throws -> [PersistentIdentifier]
    func fetchServiceDistribution(days: Int) async throws -> [String: Int]
    func fetchCategoryDistribution(days: Int) async throws -> [String: Int]
    func fetchRevenueSeries(days: Int) async throws -> [Date: Decimal]
}

@MainActor
final class DashboardRepository: DashboardRepositoryProtocol {
    private let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    func fetchKPIs() async throws -> DashboardKPI {
        let cal = Calendar.current
        let start = cal.startOfDay(for: .now)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return DashboardKPI() }

        let inProgDesc = FetchDescriptor<Visit>(
            predicate: #Predicate { v in v.endedAt == nil }
        )
        let inProgCount = try modelContext.fetchCount(inProgDesc)

        let summaryDesc = FetchDescriptor<DaySummary>(
            predicate: #Predicate { summary in summary.day >= start && summary.day < end }
        )
        let summaries = try modelContext.fetch(summaryDesc)
        let summary = SummaryUpdater.collapsedDayAggregates(from: summaries).values.first

        let yesterdayStart = cal.date(byAdding: .day, value: -1, to: start) ?? start
        let yesterdayEnd = start
        let yesterdayDesc = FetchDescriptor<DaySummary>(
            predicate: #Predicate { summary in summary.day >= yesterdayStart && summary.day < yesterdayEnd }
        )
        let yesterdaySummaries = try modelContext.fetch(yesterdayDesc)
        let yesterdaySummary = SummaryUpdater.collapsedDayAggregates(from: yesterdaySummaries).values.first

        return DashboardKPI(
            inProgressCount: inProgCount,
            revenueToday: summary?.revenue ?? .zero,
            revenueYesterday: yesterdaySummary?.revenue ?? .zero,
            completedToday: summary?.visitCount ?? 0
        )
    }
    
    func fetchActiveVisits() async throws -> [PersistentIdentifier] {
        dashboardRepoLog.info("DashboardRepository: Fetching active visits...")
        let descriptor = FetchDescriptor<Visit>(
            predicate: #Predicate { v in v.endedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        let visits = try modelContext.fetch(descriptor)
        dashboardRepoLog.info("DashboardRepository: Found \(visits.count) active visits.")
        for visit in visits {
            dashboardRepoLog.info("DashboardRepository: Visit \(visit.uuid) pet: \(visit.pet?.name ?? "unknown")")
        }
        return visits.map { $0.persistentModelID }
    }
    
    func fetchRecentClients(limit: Int) async throws -> [PersistentIdentifier] {
        var descriptor = FetchDescriptor<Client>(
            sortBy: [SortDescriptor(\.lastVisitDate, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        let clients = try modelContext.fetch(descriptor)
        return clients.map { $0.persistentModelID }
    }

    func fetchOverduePets(limit: Int) async throws -> [PersistentIdentifier] {
        var descriptor = FetchDescriptor<Pet>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.relationshipKeyPathsForPrefetching = [\.visits, \.owner]
        let pets = try modelContext.fetch(descriptor)
        let filtered = pets
            .filter { $0.isOverdue }
            .sorted {
                ($0.suggestedNextVisitDate ?? .distantFuture) < ($1.suggestedNextVisitDate ?? .distantFuture)
            }
            .prefix(limit)
        return filtered.map { $0.persistentModelID }
    }

    func fetchServiceDistribution(days: Int) async throws -> [String: Int] {
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -days, to: cal.startOfDay(for: .now)) ?? .now
        let desc = FetchDescriptor<ServiceDaySummary>(
            predicate: #Predicate { $0.day >= start }
        )
        let summaries = try modelContext.fetch(desc)
        return SummaryUpdater.collapsedServiceCounts(from: summaries)
    }

    func fetchCategoryDistribution(days: Int) async throws -> [String: Int] {
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -days, to: cal.startOfDay(for: .now)) ?? .now
        let desc = FetchDescriptor<CategoryDaySummary>(
            predicate: #Predicate { $0.day >= start }
        )
        let summaries = try modelContext.fetch(desc)
        return SummaryUpdater.collapsedCategoryCounts(from: summaries)
    }
    
    func fetchRevenueSeries(days: Int) async throws -> [Date: Decimal] {
        let cal = Calendar.current
        let end = cal.startOfDay(for: .now)
        guard let start = cal.date(byAdding: .day, value: -days + 1, to: end) else { return [:] }
        
        let desc = FetchDescriptor<DaySummary>(
            predicate: #Predicate { summary in
                summary.day >= start && summary.day <= end
            }
        )
        let summaries = try modelContext.fetch(desc)
        return SummaryUpdater.collapsedDayAggregates(from: summaries).reduce(into: [Date: Decimal]()) { dict, entry in
            dict[entry.key] = entry.value.revenue
        }
    }
    
}
