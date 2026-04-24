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

    // MARK: - Caching
    private var _cachedAgeString: String?
    private var _ageLastCalculated: Date?

    // MARK: - Relationships
    @Relationship(inverse: \Client.pets) var owner: Client?
    @Relationship(deleteRule: .cascade, inverse: \Visit.pet) var visits: [Visit] = []
    @Relationship(deleteRule: .cascade, inverse: \Appointment.pet) var appointments: [Appointment] = []
    var user: User?
    var activeVisit: Visit?

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

    /// A boolean indicating if the pet is currently checked in.
    var isCheckedIn: Bool {
        activeVisit != nil
    }

    /// A user-friendly string describing the pet's age (e.g., "3yr 6mo", "9mo").
    var ageString: String? {
        let now = Date()
        if let lastCalculated = _ageLastCalculated,
           let cached = _cachedAgeString,
           Calendar.current.isDate(now, inSameDayAs: lastCalculated) {
            return cached
        }

        guard let birthdate = self.birthdate else { return nil }
        let components = Calendar.autoupdatingCurrent.dateComponents([.year, .month], from: birthdate, to: now)

        let newAgeString: String?
        if let year = components.year, year > 0 {
            if let month = components.month, month > 0 {
                newAgeString = "\(year)yr \(month)mo"
            } else {
                newAgeString = "\(year)yr"
            }
        } else if let month = components.month, month > 0 {
            newAgeString = "\(month)mo"
        } else {
            newAgeString = nil
        }

        _cachedAgeString = newAgeString
        _ageLastCalculated = now
        return newAgeString
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
        if let date = newDate, date > Date() {
            // Silently ignore future dates or handle as error
            return
        }
        birthdate = newDate
        _cachedAgeString = nil
        _ageLastCalculated = nil
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
        if let data = data {
            photoData = ImageCache.shared.downsampleToData(data: data, maxDimension: 1024)
        } else {
            photoData = nil
        }
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
        case calm, cooperative, anxious, nervous, aggressive, specialNeeds
        var id: String { rawValue }
        
        var displayName: String {
            switch self {
            case .calm: "Calm"
            case .cooperative: "Cooperative"
            case .anxious: "Anxious"
            case .nervous: "Nervous"
            case .aggressive: "Aggressive"
            case .specialNeeds: "Special Needs"
            }
        }
    }
}
