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
    // NOTE: Non-optional properties have defaults so CloudKit can rehydrate
    // partial records. App init paths always overwrite these.
    var uuid: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    // MARK: - Contact Information
    var firstName: String = ""
    var lastName: String = ""
    var phone: String?
    var email: String?
    var address: String?
    var primaryContactInfo: String?
    @Attribute(.externalStorage) var photoData: Data?
    @Attribute(.externalStorage) var thumbnailData: Data?
    
    // MARK: - Notes & Emergency Contact
    var notes: String?
    var lastVisitDate: Date?

    // MARK: - Relationships
    @Relationship(deleteRule: .cascade, inverse: \Pet.owner) var pets: [Pet]? = []
    @Relationship(deleteRule: .cascade, inverse: \EmergencyContact.owner) var emergencyContacts: [EmergencyContact]? = []
    var user: User?

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
    
    var smsURL: URL? {
        guard let p = phone, let urlStr = PhoneUtils.smsURLString(p) else { return nil }
        return URL(string: urlStr)
    }
    
    var telURL: URL? {
        guard let p = phone, let urlStr = PhoneUtils.telURLString(p) else { return nil }
        return URL(string: urlStr)
    }
    
    /// Best-effort single-line contact summary.
    var primaryContact: String {
        if let info = primaryContactInfo, !info.isEmpty {
            return info
        }
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
        let trimmed = value?.trimmed
        if let t = trimmed, !t.isEmpty {
            phone = PhoneUtils.toE164(t) ?? t // prefer canonical E.164, fallback to trimmed
        } else {
            phone = nil
        }
        updatePrimaryContact()
        didUpdate()
    }
    func setEmail(_ value: String?) {
        let trimmed = value?.trimmed
        email = trimmed?.isEmpty == false ? trimmed?.lowercased() : nil
        updatePrimaryContact()
        didUpdate()
    }
    func setAddress(_ value: String?) {
        let trimmed = value?.trimmed
        address = trimmed?.isEmpty == false ? trimmed : nil
        didUpdate()
    }
    func setNotes(_ value: String?) {
        notes = value
        didUpdate()
    }
    func addPet(_ pet: Pet) {
        var currentPets = pets ?? []
        if !currentPets.contains(where: { $0 === pet }) {
            currentPets.append(pet)
            pets = currentPets
            didUpdate()
        }
    }
    func removePet(_ pet: Pet) {
        var currentPets = pets ?? []
        if let idx = currentPets.firstIndex(where: { $0 === pet }) {
            currentPets.remove(at: idx)
            pets = currentPets
            didUpdate()
        }
    }
    
    // MARK: - Private Helpers
    private func didUpdate() {
        updatedAt = .now
        // Spotlight indexing is nonisolated; it self-dispatches to a utility queue.
        let id = uuid
        let title = fullName
        let description = "Client with \((pets ?? []).count) pets • Phone: \(phone ?? "N/A")"
        SpotlightIndexer.shared.indexClient(id: id, title: title, description: description)
    }

    func updateThumbnail() {
        guard let data = photoData else {
            thumbnailData = nil
            return
        }
        #if canImport(UIKit) || canImport(AppKit)
        thumbnailData = ImageCache.shared.downsampleToData(data: data, maxDimension: 200)
        #endif
    }

    private func updatePrimaryContact() {
        let parts = [phone?.trimmed, email?.trimmed].compactMap { $0 }.filter { !$0.isEmpty }
        primaryContactInfo = parts.first ?? ""
    }
}
