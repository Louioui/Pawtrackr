//
//  Pet.swift
//  Pawtrackr
//
//  SwiftData model for an animal belonging to a Client.
//
//  Created by mac on 8/14/25.
//  Updated by Assistant on 8/28/25.
//

import Foundation
import SwiftData

@Model
final class Pet {
    // MARK: - Identity & Timestamps
    var uuid: UUID
    var createdAt: Date
    var updatedAt: Date

    // MARK: - Core Attributes
    var name: String
    var species: Species
    var gender: PetGender

    // MARK: - Optional Attributes
    var breed: String?
    var color: String?
    var birthdate: Date?
    @Attribute(.externalStorage) var photoData: Data?
    
    // MARK: - Notes & Behavior
    var notes: String?
    var health: String?
    var behaviorTags: [String] = []
    var specialInstructions: String?

    // MARK: - Grooming & Vet Info
    var weightLbs: Double?
    var preferredGroomingFrequency: GroomingFrequency?
    var veterinarianName: String?
    var veterinarianPhoneE164: String?

    // MARK: - Relationships
    @Relationship(inverse: \Client.pets) var owner: Client?
    @Relationship(deleteRule: .cascade) var visits: [Visit] = []
    var user: User?

    // MARK: - Init
    init(name: String, species: Species, gender: PetGender = .male) {
        self.uuid = UUID()
        self.createdAt = .now
        self.updatedAt = .now
        self.name = name.trimmed
        self.species = species
        self.gender = gender
    }

    // MARK: - Derived Properties

    /// The pet's currently active visit, if one exists.
    var activeVisit: Visit? {
        visits.first { $0.isActive }
    }

    /// A boolean indicating if the pet is currently checked in.
    var isCheckedIn: Bool {
        activeVisit != nil
    }

    /// A user-friendly string describing the pet's age (e.g., "3yr 6mo", "9mo").
    var ageString: String? {
        guard let birthdate else { return nil }
        let now = Date()
        let components = Calendar.autoupdatingCurrent.dateComponents([.year, .month], from: birthdate, to: now)
        
        if let year = components.year, year > 0 {
            if let month = components.month, month > 0 {
                return "\(year)yr \(month)mo"
            }
            return "\(year)yr"
        } else if let month = components.month, month > 0 {
            return "\(month)mo"
        }
        return nil // For pets less than a month old
    }

    /// A short, descriptive string for UI display (e.g., "Golden Retriever • Dog").
    var shortDescriptor: String {
        if let breed = breed, !breed.trimmed.isEmpty {
            return "\(breed.trimmed) • \(species.displayName)"
        }
        return species.displayName
    }
    
    // MARK: - Mutating API (ensures timestamps are updated without property observers)
    func rename(_ newName: String) {
        name = newName.trimmed
        didUpdate()
    }

    func setSpecies(_ newSpecies: Species) {
        species = newSpecies
        didUpdate()
    }

    func setGender(_ newGender: PetGender) {
        gender = newGender
        didUpdate()
    }

    func setBreed(_ newBreed: String?) {
        breed = newBreed?.trimmed
        didUpdate()
    }

    func setColor(_ newColor: String?) {
        color = newColor?.trimmed
        didUpdate()
    }

    func setBirthdate(_ newDate: Date?) {
        birthdate = newDate
        didUpdate()
    }

    func setNotes(_ newNotes: String?) {
        notes = newNotes
        didUpdate()
    }

    func setHealth(_ newHealth: String?) {
        health = newHealth
        didUpdate()
    }

    func setBehaviorTags(_ tags: [String]) {
        behaviorTags = tags.map { $0.trimmed }.filter { !$0.isEmpty }
        didUpdate()
    }

    func addBehaviorTag(_ tag: String) {
        let t = tag.trimmed
        guard !t.isEmpty else { return }
        if !behaviorTags.contains(where: { $0.caseInsensitiveCompare(t) == .orderedSame }) {
            behaviorTags.append(t)
            didUpdate()
        }
    }

    func removeBehaviorTag(_ tag: String) {
        let t = tag.trimmed
        if let idx = behaviorTags.firstIndex(where: { $0.caseInsensitiveCompare(t) == .orderedSame }) {
            behaviorTags.remove(at: idx)
            didUpdate()
        }
    }

    func setSpecialInstructions(_ value: String?) {
        specialInstructions = value
        didUpdate()
    }

    func setWeightLbs(_ value: Double?) {
        if let v = value { weightLbs = max(0, v) } else { weightLbs = nil }
        didUpdate()
    }

    func setPreferredGroomingFrequency(_ value: GroomingFrequency?) {
        preferredGroomingFrequency = value
        didUpdate()
    }

    func setVeterinarian(name: String?, phoneE164: String?) {
        veterinarianName = name?.trimmed
        veterinarianPhoneE164 = phoneE164?.trimmed
        didUpdate()
    }

    func setPhotoData(_ data: Data?) {
        photoData = data
        didUpdate()
    }
    
    // MARK: - Private Helpers
    private func didUpdate() {
        updatedAt = .now
    }
}

// MARK: - Nested Enums
extension Pet {
    /// Standardized options for grooming frequency.
    enum GroomingFrequency: String, Codable, CaseIterable, Identifiable {
        case weekly, biWeekly, monthly, quarterly, asNeeded
        var id: String { rawValue }
        
        var displayName: String {
            switch self {
            case .weekly: "Weekly"
            case .biWeekly: "Every 2 Weeks"
            case .monthly: "Monthly"
            case .quarterly: "Every 3 Months"
            case .asNeeded: "As Needed"
            }
        }
    }
    
    /// Standardized, common behavior tags for consistent data entry.
    enum BehaviorTag: String, CaseIterable, Identifiable {
        case calm, cooperative, anxious, nervous, aggressive, senior, puppy, specialNeeds, bites
        var id: String { rawValue }
        
        var displayName: String {
            switch self {
            case .calm: "Calm"
            case .cooperative: "Cooperative"
            case .anxious: "Anxious"
            case .nervous: "Nervous"
            case .aggressive: "Aggressive"
            case .senior: "Senior"
            case .puppy: "Puppy / Young"
            case .specialNeeds: "Special Needs"
            case .bites: "Bites"
            }
        }
    }
}
