//
//  Client+Extensions.swift
//  Pawtrackr
//
//  Created by Assistant on 2025-09-03.
//

import Foundation

// IMPROVEMENT: Centralize reusable business logic on the model itself.
extension Client {
    /// A boolean indicating if any of the client's pets are currently checked in for a visit.
    var hasActiveVisit: Bool {
        for pet in pets {
            if pet.visits.contains(where: { $0.isActive }) {
                return true
            }
        }
        return false
    }

    /// The start time of the most recent active visit, used for sorting "In Progress" clients.
    var sortKeyMostRecentVisit: Date {
        pets.flatMap { $0.visits }
            .map { $0.sortKeyDate }
            .max() ?? .distantPast
    }

    /// The most recent active visit object across all of this client's pets.
    var mostRecentActiveVisit: Visit? {
        pets.flatMap { $0.visits }
            .filter { $0.isActive }
            .max(by: { $0.startedAt < $1.startedAt })
    }

    /// The end time of the most recent completed visit across all pets.
    var mostRecentEndedAt: Date? {
        pets.flatMap { $0.visits }
            .compactMap { $0.endedAt }
            .max()
    }
}
