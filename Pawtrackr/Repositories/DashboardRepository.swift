//
//  DashboardRepository.swift
//  Pawtrackr
//

import Foundation
import SwiftData

struct DashboardKPI {
    var appointmentsToday: Int = 0
    var inProgressCount: Int = 0
    var revenueToday: Decimal = .zero
    var completedToday: Int = 0
}

@MainActor
protocol DashboardRepositoryProtocol: Sendable {
    func fetchKPIs() async throws -> DashboardKPI
    func fetchActiveVisits() async throws -> [Visit]
    func fetchRecentClients(limit: Int) async throws -> [Client]
    func fetchRevenueSeries(days: Int) async throws -> [Date: Decimal]
    func fetchGalleryImages(days: Int, limit: Int) async throws -> [Data]
}

@MainActor
final class DashboardRepository: DashboardRepositoryProtocol {
    private let modelContext: ModelContext
    
    init(modelContainer: ModelContainer) {
        self.modelContext = modelContainer.mainContext
    }
    
    func fetchKPIs() async throws -> DashboardKPI {
        let cal = Calendar.current
        let start = cal.startOfDay(for: .now)
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        
        // Today's appointments (visits started today)
        let todayDesc = FetchDescriptor<Visit>(
            predicate: #Predicate { v in v.startedAt >= start && v.startedAt < end }
        )
        let todaysCount = try modelContext.fetchCount(todayDesc)
        
        // In progress
        let inProgDesc = FetchDescriptor<Visit>(
            predicate: #Predicate { v in v.endedAt == nil }
        )
        let inProgCount = try modelContext.fetchCount(inProgDesc)
        
        // Revenue and completed count from DaySummary
        let summaryDesc = FetchDescriptor<DaySummary>(
            predicate: #Predicate { summary in summary.day >= start && summary.day < end }
        )
        let summary = try modelContext.fetch(summaryDesc).first
        
        return DashboardKPI(
            appointmentsToday: todaysCount,
            inProgressCount: inProgCount,
            revenueToday: summary?.revenue ?? .zero,
            completedToday: summary?.visitCount ?? 0
        )
    }
    
    func fetchActiveVisits() async throws -> [Visit] {
        let descriptor = FetchDescriptor<Visit>(
            predicate: #Predicate { v in v.endedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }
    
    func fetchRecentClients(limit: Int) async throws -> [Client] {
        var descriptor = FetchDescriptor<Client>(
            sortBy: [SortDescriptor(\.lastVisitDate, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor)
    }
    
    func fetchRevenueSeries(days: Int) async throws -> [Date: Decimal] {
        let cal = Calendar.current
        let end = cal.startOfDay(for: .now)
        let start = cal.date(byAdding: .day, value: -days + 1, to: end)!
        
        let desc = FetchDescriptor<DaySummary>(
            predicate: #Predicate { summary in
                summary.day >= start && summary.day <= end
            }
        )
        let summaries = try modelContext.fetch(desc)
        return summaries.reduce(into: [Date: Decimal]()) { dict, summary in
            dict[summary.day] = summary.revenue
        }
    }
    
    func fetchGalleryImages(days: Int, limit: Int) async throws -> [Data] {
        let cal = Calendar.current
        let end = cal.startOfDay(for: .now)
        guard let start = cal.date(byAdding: .day, value: -days, to: end) else { return [] }
        
        let desc = FetchDescriptor<Visit>(
            predicate: #Predicate { v in v.startedAt >= start && v.startedAt < end },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        // Note: fetchLimit doesn't always work as expected with complex predicates in SwiftData 
        // if the underlying storage is CloudKit, but for local it should be fine.
        var descriptor = desc
        descriptor.fetchLimit = limit * 2 // Fetch a bit more to account for visits without photos
        
        let visits = try modelContext.fetch(descriptor)
        return visits.compactMap { $0.afterPhotoData ?? $0.beforePhotoData }.prefix(limit).map { $0 }
    }
}
