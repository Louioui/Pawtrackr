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
    @Attribute(.externalStorage) var thumbnailData: Data?
    
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

    // MARK: - Prediction Engine (Business Intelligence)

    /// Calculates the average time (in seconds) between completed visits.
    var averageVisitInterval: TimeInterval? {
        let completedVisits = visits
            .filter { $0.isCompleted }
            .sorted { $0.startedAt < $1.startedAt }
        
        guard completedVisits.count >= 2 else { return nil }
        
        var totalInterval: TimeInterval = 0
        for i in 1..<completedVisits.count {
            totalInterval += completedVisits[i].startedAt.timeIntervalSince(completedVisits[i-1].startedAt)
        }
        
        return totalInterval / Double(completedVisits.count - 1)
    }

    /// Predicts the next suggested grooming date based on history or preferred frequency.
    var suggestedNextVisitDate: Date? {
        // 1. If there's an active visit or a future appointment, we don't need a suggestion
        if isCheckedIn { return nil }
        
        // Ensure at least one completed visit exists to base prediction on
        guard visits.contains(where: { $0.isCompleted }) else { return nil }
        
        let futureAppointments = appointments.filter { $0.date > .now }
        if !futureAppointments.isEmpty { return nil }

        // 2. Get the last visit date
        guard let lastVisitDate = visits.compactMap({ $0.endedAt }).max() else {
            return nil
        }

        // 3. Determine the interval to use
        let interval: TimeInterval
        if let avg = averageVisitInterval {
            interval = avg
        } else if let preferred = preferredGroomingFrequency {
            switch preferred {
            case .weekly: interval = 7 * 24 * 3600
            case .biWeekly: interval = 14 * 24 * 3600
            case .monthly: interval = 30 * 24 * 3600
            case .quarterly: interval = 90 * 24 * 3600
            case .asNeeded: return nil
            }
        } else {
            // Default to 6 weeks if no history or preference
            interval = 42 * 24 * 3600
        }

        return lastVisitDate.addingTimeInterval(interval)
    }

    /// Returns true if the pet is overdue for their next suggested visit.
    var isOverdue: Bool {
        guard let suggested = suggestedNextVisitDate else { return false }
        return Date() > suggested
    }

    /// Human-readable string indicating when the next visit is expected or how overdue it is.
    var nextVisitStatus: String? {
        guard let suggested = suggestedNextVisitDate else { return nil }
        
        let now = Date()
        let cal = Calendar.current
        
        if now > suggested {
            let days = cal.dateComponents([.day], from: suggested, to: now).day ?? 0
            return days == 0 ? "Due today" : "\(days)d overdue"
        } else {
            let days = cal.dateComponents([.day], from: now, to: suggested).day ?? 0
            if days == 0 { return "Due today" }
            if days == 1 { return "Due tomorrow" }
            return "Due in \(days)d"
        }
    }

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

    func updateThumbnail() {
        guard let data = photoData else {
            thumbnailData = nil
            return
        }
        // Downsample to a small 200px thumbnail for high-performance list rendering
        #if canImport(UIKit) || canImport(AppKit)
        thumbnailData = ImageCache.shared.downsampleToData(data: data, maxDimension: 200)
        #endif
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
