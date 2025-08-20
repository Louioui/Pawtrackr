//  Client.swift
//  Pawtrackr
//
//  SwiftData model for a pet owner (client).
//  - First/last name, phone, email, address, notes
//  - One‑to‑many relationship to Pet (cascade delete)
//  - Convenience computed properties
//
//  Created by mac on 8/14/25.
//  Updated by mac on 8/17/25.
//

import Foundation
import SwiftData

@Model
final class Client {
    // MARK: - Identity & timestamps
    /// Stable identifier you can use in exports/URLs (distinct from SwiftData's internal ID)
    var uuid: UUID
    var createdAt: Date
    var updatedAt: Date

    // MARK: - Contact
    var firstName: String
    var lastName: String
    var phone: String?      // store digits or E.164; format at the UI layer
    var email: String?
    var address: String?
    var notes: String?
    var emergencyContact: String? // Added to match the New Client form

    // MARK: - Relationships
    @Relationship(deleteRule: .cascade) var pets: [Pet] = []

    // MARK: - Init
    init(firstName: String, lastName: String, phone: String? = nil, email: String? = nil) {
        self.uuid = UUID()
        self.createdAt = Date()
        self.updatedAt = Date()
        self.firstName = firstName
        self.lastName = lastName
        self.phone = phone
        self.email = email
    }

    // MARK: - Derived
    var fullName: String {
        [firstName.trimmed, lastName.trimmed].filter { !$0.isEmpty }.joined(separator: " ")
    }

    var hasActiveVisit: Bool {
        pets.contains { pet in pet.visits.contains { $0.endedAt == nil } }
    }

    // Keep updatedAt fresh when mutable fields change
    func touch() { updatedAt = Date() }
}

// MARK: - Helpers

fileprivate extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
