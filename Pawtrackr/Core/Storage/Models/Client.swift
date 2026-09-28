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
    #Index<Client>([\.lastName, \.firstName], [\.lastVisitDate])

    // MARK: - Identity & Timestamps
    // NOTE: Non-optional properties have defaults so CloudKit can rehydrate
    // partial records. App init paths always overwrite these.
    var uuid: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var lastModifiedBy: UUID = DeviceIdentity.currentID

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
    var loyaltyPoints: Int = 0

    // MARK: - Relationships
    @Relationship(deleteRule: .cascade, inverse: \Pet.owner) var pets: [Pet]? = []
    @Relationship(deleteRule: .cascade, inverse: \EmergencyContact.owner) var emergencyContacts: [EmergencyContact]? = []
    var user: User?

    // MARK: - Init
    init(firstName: String, lastName: String, phone: String? = nil, email: String? = nil) {
        self.uuid = UUID()
        self.createdAt = .now
        self.updatedAt = .now
        self.firstName = TextInputLimits.clamped(firstName, to: TextInputLimits.name)
        self.lastName = TextInputLimits.clamped(lastName, to: TextInputLimits.name)
        self.phone = TextInputLimits.clampedOptional(phone, to: TextInputLimits.phone)
        self.email = TextInputLimits.clampedOptional(email, to: TextInputLimits.email)?.lowercased()
        updatePrimaryContact()
    }

    // MARK: - Derived Properties
    
    /// The client's full name, created by joining the first and last names.
    var fullName: String {
        [firstName.trimmed, lastName.trimmed]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// True when any of this client's pets is flagged aggressive. Single source of
    /// truth for the staff-safety warning shown on the client list and detail.
    /// Computed (not stored) so it stays schema/CloudKit-safe and always reflects
    /// the current behavior tags.
    var hasAggressivePet: Bool {
        (pets ?? []).contains { $0.isAggressive }
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
    //
    // Each setter compares before assigning. SwiftData marks a row changed on
    // any assignment, even of the same value, and every changed row uploads to
    // iCloud and imports on every other device. A no-op Save would also stamp
    // updatedAt/lastModifiedBy and look like a real edit from this device to
    // the edit-conflict check on the others.
    func setFirstName(_ value: String) {
        let newValue = TextInputLimits.clamped(value, to: TextInputLimits.name)
        guard firstName != newValue else { return }
        firstName = newValue
        didUpdate(ownerDetailsChanged: true)
    }
    func setLastName(_ value: String) {
        let newValue = TextInputLimits.clamped(value, to: TextInputLimits.name)
        guard lastName != newValue else { return }
        lastName = newValue
        didUpdate(ownerDetailsChanged: true)
    }
    func setPhone(_ value: String?) {
        let trimmed = TextInputLimits.clampedOptional(value, to: TextInputLimits.phone)
        let newValue: String?
        if let t = trimmed, !t.isEmpty {
            // Prefer canonical E.164. If the input doesn't parse, fall back to
            // the user's literal text — but `findClient(byPhone:)` normalizes
            // both stored and lookup values, so unparseable phones still match.
            newValue = PhoneUtils.toE164(t) ?? t
        } else {
            newValue = nil
        }
        guard phone != newValue else { return }
        phone = newValue
        updatePrimaryContact()
        didUpdate(ownerDetailsChanged: true)
    }
    func setEmail(_ value: String?) {
        let trimmed = TextInputLimits.clampedOptional(value, to: TextInputLimits.email)
        let newValue = trimmed?.isEmpty == false ? trimmed?.lowercased() : nil
        guard email != newValue else { return }
        email = newValue
        updatePrimaryContact()
        didUpdate()
    }
    func setAddress(_ value: String?) {
        let trimmed = TextInputLimits.clampedOptional(value, to: TextInputLimits.address)
        let newValue = trimmed?.isEmpty == false ? trimmed : nil
        guard address != newValue else { return }
        address = newValue
        didUpdate()
    }
    func setNotes(_ value: String?) {
        let newValue = TextInputLimits.clampedOptional(value, to: TextInputLimits.notes)
        guard notes != newValue else { return }
        notes = newValue
        didUpdate()
    }
    func addPet(_ pet: Pet) {
        var currentPets = pets ?? []
        if !currentPets.contains(where: { $0 === pet }) {
            currentPets.append(pet)
            pets = currentPets
            didUpdate(ownerDetailsChanged: true)
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

    func setPhotoData(_ data: Data?) {
        if let data = data {
            photoData = CloudMediaPolicy.optimizedFullImageData(data, context: "client profile photo")
            updateThumbnail()
        } else {
            photoData = nil
            thumbnailData = nil
        }
        didUpdate()
    }
    
    // MARK: - Private Helpers
    /// `ownerDetailsChanged`: the name or phone changed, or a pet was added.
    /// Pet items carry the owner's name and phone, so those re-index too.
    private func didUpdate(ownerDetailsChanged: Bool = false) {
        updatedAt = .now
        lastModifiedBy = DeviceIdentity.currentID
        // Snapshots on this thread, then debounces per id on the indexer's
        // queue, so a multi-field edit (name + phone + email) is one write.
        // Skipped entirely while App Lock keeps Pawtrackr out of Spotlight.
        SpotlightIndexer.shared.scheduleIndex(client: self, includingPets: ownerDetailsChanged)
    }

    func updateThumbnail() {
        guard let data = photoData else {
            thumbnailData = nil
            return
        }
        #if canImport(UIKit) || canImport(AppKit)
        thumbnailData = CloudMediaPolicy.optimizedThumbnailData(data)
        #endif
    }

    private func updatePrimaryContact() {
        let parts = [phone?.trimmed, email?.trimmed].compactMap { $0 }.filter { !$0.isEmpty }
        let newValue = parts.first ?? ""
        if primaryContactInfo != newValue { primaryContactInfo = newValue }
    }
}
