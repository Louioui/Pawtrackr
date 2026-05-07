//
//  DashboardRepository.swift
//  Pawtrackr
//

import Foundation
import SwiftData
import OSLog

private let dashboardRepoLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "DashboardRepository")

struct DashboardKPI {
    var appointmentsToday: Int = 0
    var inProgressCount: Int = 0
    var revenueToday: Decimal = .zero
    var revenueYesterday: Decimal = .zero
    var completedToday: Int = 0
}

@MainActor
protocol DashboardRepositoryProtocol: Sendable {
    var modelContext: ModelContext { get }
    func fetchKPIs() async throws -> DashboardKPI
    func fetchActiveVisits() async throws -> [Visit]
    func fetchUpcomingAppointments(limit: Int) async throws -> [Appointment]
    func fetchRecentClients(limit: Int) async throws -> [Client]
    func fetchOverduePets(limit: Int) async throws -> [Pet]
    func fetchServiceDistribution(days: Int) async throws -> [String: Int]
    func fetchCategoryDistribution(days: Int) async throws -> [String: Int]
    func fetchRevenueSeries(days: Int) async throws -> [Date: Decimal]
    func fetchGalleryImages(days: Int, limit: Int) async throws -> [Data]
}

@MainActor
final class DashboardRepository: DashboardRepositoryProtocol {
    let modelContext: ModelContext
    
    init(modelContainer: ModelContainer) {
        self.modelContext = modelContainer.mainContext
    }
    
    func fetchKPIs() async throws -> DashboardKPI {
        let cal = Calendar.current
        let start = cal.startOfDay(for: .now)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return DashboardKPI() }

        do {
            let todayApptDesc = FetchDescriptor<Appointment>(
                predicate: #Predicate { a in a.date >= start && a.date < end }
            )
            let todaysCount = try modelContext.fetchCount(todayApptDesc)

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
                appointmentsToday: todaysCount,
                inProgressCount: inProgCount,
                revenueToday: summary?.revenue ?? .zero,
                revenueYesterday: yesterdaySummary?.revenue ?? .zero,
                completedToday: summary?.visitCount ?? 0
            )
        } catch {
            dashboardRepoLog.error("fetchKPIs failed: \(String(describing: error))")
            throw error
        }
    }
    
    func fetchActiveVisits() async throws -> [Visit] {
        let descriptor = FetchDescriptor<Visit>(
            predicate: #Predicate { v in v.endedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            dashboardRepoLog.error("fetchActiveVisits failed: \(String(describing: error))")
            throw error
        }
    }

    func fetchUpcomingAppointments(limit: Int) async throws -> [Appointment] {
        let now = Date()
        // Filter by date in the predicate; filter status in memory.
        // SwiftData's #Predicate compiler does not reliably translate
        // captured enum comparisons into SQL, so doing the status filter
        // in memory is the safe path.
        let descriptor = FetchDescriptor<Appointment>(
            predicate: #Predicate { a in a.date >= now },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        do {
            let upcoming = try modelContext.fetch(descriptor)
            return Array(upcoming.filter { $0.status == .scheduled }.prefix(limit))
        } catch {
            dashboardRepoLog.error("fetchUpcomingAppointments failed: \(String(describing: error))")
            throw error
        }
    }
    
    func fetchRecentClients(limit: Int) async throws -> [Client] {
        var descriptor = FetchDescriptor<Client>(
            sortBy: [SortDescriptor(\.lastVisitDate, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            dashboardRepoLog.error("fetchRecentClients failed: \(String(describing: error))")
            throw error
        }
    }

    func fetchOverduePets(limit: Int) async throws -> [Pet] {
        let descriptor = FetchDescriptor<Pet>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        do {
            let pets = try modelContext.fetch(descriptor)
            return Array(pets.filter { $0.isOverdue }.prefix(limit))
        } catch {
            dashboardRepoLog.error("fetchOverduePets failed: \(String(describing: error))")
            throw error
        }
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
    
    func fetchGalleryImages(days: Int, limit: Int) async throws -> [Data] {
        let cal = Calendar.current
        let end = cal.startOfDay(for: .now)
        guard let start = cal.date(byAdding: .day, value: -days, to: end) else { return [] }

        var descriptor = FetchDescriptor<Visit>(
            predicate: #Predicate { v in v.startedAt >= start && v.startedAt < end },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit * 2

        let visits = try modelContext.fetch(descriptor)
        return visits
            .compactMap { $0.afterThumbnailData ?? $0.beforeThumbnailData }
            .prefix(limit)
            .map { $0 }
    }
}
