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
            if daysSinceLastVisit > (avgInterval * 1.2) {
                let weeks = Int(avgInterval / (7 * 24 * 3600))
                let suggestion = SmartSuggestion(
                    petID: pet.persistentModelID,
                    clientID: pet.owner?.persistentModelID,
                    petName: pet.name,
                    ownerName: pet.owner?.fullName ?? "Unknown Owner",
                    message: "\(pet.name) usually visits every \(weeks) weeks. It's been \(Int(daysSinceLastVisit / (24 * 3600))) days since their last visit.",
                    actionType: .text
                )
                suggestions.append(suggestion)
            }
        }
        
        return suggestions.sorted { $0.message.count < $1.message.count } // Simple sort for now
    }
}
