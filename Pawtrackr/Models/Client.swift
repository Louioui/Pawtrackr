//
//  Client.swift
//  Pawtrackr
//
//  SwiftData model for a pet owner (client).
//
//  Created by mac on 8/14/25.
//  Updated by Assistant on 8/28/25.
//

import Foundation
import SwiftData

@Model
final class Client {
    // MARK: - Identity & Timestamps
    var uuid: UUID
    var createdAt: Date
    var updatedAt: Date

    // MARK: - Contact Information
    var firstName: String
    var lastName: String
    var phone: String?
    var email: String?
    var address: String?
    
    // MARK: - Notes & Emergency Contact
    var notes: String?
    var emergencyContactName: String?
    var emergencyContactPhone: String?

    // MARK: - Relationships
    @Relationship(deleteRule: .cascade) var pets: [Pet] = []

    // MARK: - Init
    init(firstName: String, lastName: String, phone: String? = nil, email: String? = nil) {
        self.uuid = UUID()
        self.createdAt = .now
        self.updatedAt = .now
        self.firstName = firstName.trimmed
        self.lastName = lastName.trimmed
        self.phone = phone?.trimmed
        self.email = email?.trimmed
    }

    // MARK: - Derived Properties
    
    /// The client's full name, created by joining the first and last names.
    var fullName: String {
        [firstName.trimmed, lastName.trimmed]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
    
    /// Best-effort single-line contact summary.
    var primaryContact: String {
        let parts = [phone?.trimmed, email?.trimmed].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.first ?? ""
    }

    // MARK: - Mutating API (keeps timestamps correct without property observers)
    func setFirstName(_ value: String) {
        firstName = value.trimmed
        didUpdate()
    }
    func setLastName(_ value: String) {
        lastName = value.trimmed
        didUpdate()
    }
    func setPhone(_ value: String?) {
        phone = value?.trimmed
        didUpdate()
    }
    func setEmail(_ value: String?) {
        email = value?.trimmed
        didUpdate()
    }
    func setAddress(_ value: String?) {
        address = value?.trimmed
        didUpdate()
    }
    func setNotes(_ value: String?) {
        notes = value
        didUpdate()
    }
    func setEmergencyContact(name: String?, phone: String?) {
        emergencyContactName = name?.trimmed
        emergencyContactPhone = phone?.trimmed
        didUpdate()
    }
    func addPet(_ pet: Pet) {
        if !pets.contains(where: { $0 === pet }) {
            pets.append(pet)
            didUpdate()
        }
    }
    func removePet(_ pet: Pet) {
        if let idx = pets.firstIndex(where: { $0 === pet }) {
            pets.remove(at: idx)
            didUpdate()
        }
    }
    
    // MARK: - Private Helpers
    private func didUpdate() {
        updatedAt = .now
    }
}

// MARK: - Helpers
fileprivate extension String {
    /// Returns the string with leading and trailing whitespace and newlines removed.
    var trimmed: String {
        self.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
