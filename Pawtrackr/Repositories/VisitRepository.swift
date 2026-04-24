//
//  VisitRepository.swift
//  Pawtrackr
//
//  Manages Visit lifecycle and operations.
//

import Foundation
import SwiftData
import OSLog

@MainActor
protocol VisitRepositoryProtocol: Sendable {
    func fetchVisits(predicate: Predicate<Visit>?, sortBy: [SortDescriptor<Visit>], limit: Int?) async throws -> [Visit]
    func saveVisit(_ visit: Visit) async throws
    func deleteVisit(_ visit: Visit) async throws
    func checkIn(pet: Pet, date: Date) async throws -> Visit
    func checkOut(visit: Visit, total: Decimal?, now: Date) async throws
}

@MainActor
final class VisitRepository: VisitRepositoryProtocol {
    private let modelContext: ModelContext
    
    init(modelContainer: ModelContainer) {
        self.modelContext = modelContainer.mainContext
    }
    
    func fetchVisits(predicate: Predicate<Visit>?, sortBy: [SortDescriptor<Visit>], limit: Int?) async throws -> [Visit] {
        var descriptor = FetchDescriptor<Visit>(predicate: predicate, sortBy: sortBy)
        if let limit = limit {
            descriptor.fetchLimit = limit
        }
        return try modelContext.fetch(descriptor)
    }
    
    func saveVisit(_ visit: Visit) async throws {
        if visit.modelContext == nil {
            modelContext.insert(visit)
        }
        try modelContext.save()
    }
    
    func deleteVisit(_ visit: Visit) async throws {
        let dateToRebuild = visit.endedAt
        modelContext.delete(visit)
        try modelContext.save()
        
        // If it was a completed visit, rebuild summary for that day
        if let ended = dateToRebuild {
            SummaryUpdater.rebuildDay(for: ended, in: modelContext)
            let userInfo: [String: Any] = [
                VisitDidCompleteKey.endedAt.rawValue: ended
            ]
            NotificationCenter.default.post(name: .visitDidComplete, object: nil, userInfo: userInfo)
        }
    }
    
    func checkIn(pet: Pet, date: Date) async throws -> Visit {
        let visit = Visit(pet: pet, startedAt: date)
        modelContext.insert(visit)
        try modelContext.save()
        return visit
    }
    
    func checkOut(visit: Visit, total: Decimal?, now: Date) async throws {
        Logger.main.info("VisitRepository: Checking out visit \(visit.uuid)")
        visit.markCheckedOut(total: total, now: now)
        
        // Save the visit and its payment
        try modelContext.save()
        
        // Only post notification. PawtrackrApp's listener will handle 
        // the heavy summary rebuilding in a detached background task.
        let userInfo: [String: Any] = [
            VisitDidCompleteKey.endedAt.rawValue: now
        ]
        NotificationCenter.default.post(name: .visitDidComplete, object: visit, userInfo: userInfo)
        Logger.main.info("VisitRepository: Checkout complete, notification posted")
    }
}
