//
//  Pet.swift
//  Pawtrackr
//
//  SwiftData model for an animal belonging to a Client.
//  Supports species (dog/cat), gender (male/female/unknown), optional photo,
//  attributes like breed/color, and relationships to owner & visits.
//
//  Created by mac on 8/14/25.
//  Updated by mac on 8/17/25.
//

import Foundation
import SwiftData

@Model
final class Pet {
    // MARK: - Identity & timestamps
    var uuid: UUID
    var createdAt: Date
    var updatedAt: Date

    // MARK: - Basics
    var name: String
    var species: Species
    var gender: PetGender

    // MARK: - Optional attributes
    var breed: String?
    var color: String?
    var birthdate: Date?    // if provided, UI can derive age string
    var notes: String?
    var health: String?     // free text health flags (e.g., allergies)
    var behaviorTags: [String] = [] // e.g., ["Friendly","Nervous","Senior","Needs Muzzle"]

    // Pet photo, stored as JPEG/PNG bytes (UI decodes to UIImage)
    var photoData: Data?

    // MARK: - Relationships
    @Relationship(inverse: \Client.pets) var owner: Client?
    @Relationship(deleteRule: .cascade) var visits: [Visit] = []

    // MARK: - Init
    init(name: String, species: Species, gender: PetGender = .unknown) {
        self.uuid = UUID()
        self.createdAt = Date()
        self.updatedAt = Date()
        self.name = name
        self.species = species
        self.gender = gender
    }

    // MARK: - Derived
    var activeVisit: Visit? { visits.first { $0.endedAt == nil } }
    var isCheckedIn: Bool { activeVisit != nil }

    /// Returns a short descriptor like "Golden Retriever • Dog" or just "Dog"
    var shortDescriptor: String {
        if let breed, !breed.isEmpty { return "\(breed) • \(species.rawValue.capitalized)" }
        return species.rawValue.capitalized
    }

    func touch() { updatedAt = Date() }
}

