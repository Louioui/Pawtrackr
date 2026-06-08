//
//  PredictiveSchedulingActor.swift
//  Pawtrackr
//
//  Advanced background actor for predictive business intelligence.
//  Analyzes pet visit history to identify churn risk and suggest re-engagement.
//

import Foundation
import SwiftData
import OSLog

private let predictiveLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "PredictiveScheduling")

struct SmartSuggestion: Identifiable, Sendable {
    let id = UUID()
    let petID: PersistentIdentifier
    let clientID: PersistentIdentifier?
    let petName: String
    let ownerName: String
    let message: String
    let actionType: ActionType
    /// Days overdue divided by typical interval. Higher = more urgent.
    /// Used to sort suggestions so the groomer sees the most-overdue pets first.
    let overdueRatio: Double

    enum ActionType: Sendable {
        case call, text, rebook
    }
}

@ModelActor
final actor PredictiveSchedulingActor {
    
    func generateSuggestions() async throws -> [SmartSuggestion] {
        let context = modelContext
        
        // 1. Fetch all pets with their visit history
        var descriptor = FetchDescriptor<Pet>()
        descriptor.relationshipKeyPathsForPrefetching = [\.visits, \.owner]
        let pets = try context.fetch(descriptor)
        
        var suggestions: [SmartSuggestion] = []
        
        for pet in pets {
            guard let visits = pet.visits, visits.count >= 2 else { continue }
            
            // Calculate average interval between visits
            let sortedVisits = visits.filter { $0.isCompleted }.sorted { $0.startedAt < $1.startedAt }
            guard sortedVisits.count >= 2 else { continue }
            
            var intervals: [TimeInterval] = []
            for i in 1..<sortedVisits.count {
                let interval = sortedVisits[i].startedAt.timeIntervalSince(sortedVisits[i-1].startedAt)
                intervals.append(interval)
            }
            
            let avgInterval = intervals.reduce(0, +) / Double(intervals.count)
            let lastVisitDate = sortedVisits.last?.startedAt ?? .distantPast
            let daysSinceLastVisit = Date.now.timeIntervalSince(lastVisitDate)
            
            // Suggest re-engagement if pet is 20% past their typical schedule
            if avgInterval > 0, daysSinceLastVisit > (avgInterval * 1.2) {
                let weeks = max(1, Int(avgInterval / (7 * 24 * 3600)))
                let weeksWord = weeks == 1 ? "week" : "weeks"
                let expectedDate = lastVisitDate.addingTimeInterval(avgInterval)
                let daysOverdue = max(
                    1,
                    Calendar.current.dateComponents([.day], from: expectedDate, to: Date.now).day ?? 1
                )
                let actionType: SmartSuggestion.ActionType
                if pet.owner?.smsURL != nil {
                    actionType = .text
                } else if pet.owner?.telURL != nil {
                    actionType = .call
                } else {
                    actionType = .rebook
                }
                let suggestion = SmartSuggestion(
                    petID: pet.persistentModelID,
                    clientID: pet.owner?.persistentModelID,
                    petName: pet.name,
                    ownerName: pet.owner?.fullName ?? "Unknown Owner",
                    message: "\(pet.name) is \(daysOverdue)d past their usual \(weeks) \(weeksWord) cadence. Last visit \(lastVisitDate.formatted(date: .abbreviated, time: .omitted)).",
                    actionType: actionType,
                    overdueRatio: daysSinceLastVisit / avgInterval
                )
                suggestions.append(suggestion)
            }
        }

        // Most overdue first.
        return suggestions.sorted { $0.overdueRatio > $1.overdueRatio }
    }
}
