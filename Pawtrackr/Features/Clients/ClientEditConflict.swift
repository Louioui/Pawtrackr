//
//  ClientEditConflict.swift
//  Pawtrackr
//
//  Guards the client edit forms (Edit Client sheet and the inline header
//  edit) against silently overwriting a change another device saved while
//  the form was open.
//
//  Why this can be trusted without a schema change:
//  - Both forms edit copies in @State, never the live model, until Save.
//  - Every path that writes a client's name, phone, email or address goes
//    through the Client setters, which stamp updatedAt and lastModifiedBy
//    (and, since they compare first, only when a value really changed).
//  - updatedAt and lastModifiedBy are ordinary synced fields, so an edit
//    loaded from another context carries its saved values.
//  - The check re-reads the client through a fresh ModelContext, so a change
//    the view's context hasn't merged yet still counts.
//
//  Save writes only the fields the groomer changed, onto a copy re-read from
//  the store, so a different field changed elsewhere survives "Save My
//  Changes".
//

import Foundation
import SwiftData
import OSLog

/// The client fields the edit forms change, as the Client setters store them.
struct ClientContactFields: Equatable, Sendable {
    enum Field: Hashable, Sendable, CaseIterable {
        case firstName
        case lastName
        case phone
        case email
        case address
    }

    var firstName: String
    var lastName: String
    var phone: String?
    var email: String?
    var address: String?

    init(firstName: String, lastName: String, phone: String?, email: String?, address: String?) {
        self.firstName = firstName
        self.lastName = lastName
        self.phone = phone
        self.email = email
        self.address = address
    }

    init(_ client: Client) {
        self.init(
            firstName: client.firstName,
            lastName: client.lastName,
            phone: client.phone,
            email: client.email,
            address: client.address
        )
    }

    /// The text a form shows for a stored phone. A stored value PhoneUtils
    /// can't format (older data) is shown as stored rather than as blank,
    /// which used to make Save clear it.
    static func formPhoneText(_ stored: String?) -> String {
        guard let stored, !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        return PhoneUtils.display(stored) ?? stored
    }

    func changedFields(comparedTo other: ClientContactFields) -> Set<Field> {
        var changed = Set<Field>()
        if firstName != other.firstName { changed.insert(.firstName) }
        if lastName != other.lastName { changed.insert(.lastName) }
        if phone != other.phone { changed.insert(.phone) }
        if email != other.email { changed.insert(.email) }
        if address != other.address { changed.insert(.address) }
        return changed
    }
}

/// What the form showed when it opened.
struct ClientEditBaseline: Equatable, Sendable {
    let clientUUID: UUID
    let updatedAt: Date
    let lastModifiedBy: UUID
    let fields: ClientContactFields

    init(clientUUID: UUID, updatedAt: Date, lastModifiedBy: UUID, fields: ClientContactFields) {
        self.clientUUID = clientUUID
        self.updatedAt = updatedAt
        self.lastModifiedBy = lastModifiedBy
        self.fields = fields
    }

    init(_ client: Client) {
        self.init(
            clientUUID: client.uuid,
            updatedAt: client.updatedAt,
            lastModifiedBy: client.lastModifiedBy,
            fields: ClientContactFields(client)
        )
    }

    /// True when another device saved a change to one of the form's fields
    /// after the form opened. A newer stamp alone isn't enough: adding a pet
    /// or earning points stamps the client too, without touching the form.
    /// Neither is a change this device made itself.
    func hasChangeFromAnotherDevice(current: ClientEditBaseline, currentDeviceID: UUID) -> Bool {
        current.updatedAt > updatedAt
            && current.lastModifiedBy != currentDeviceID
            && current.fields != fields
    }
}

/// The form's text, normalized the way the Client setters store it.
struct ClientEditForm: Equatable, Sendable {
    var firstName: String
    var lastName: String
    var phone: String
    var email: String
    /// nil when the form has no address field (the inline header edit):
    /// the stored address is kept.
    var address: String?

    init(firstName: String, lastName: String, phone: String, email: String, address: String?) {
        self.firstName = firstName
        self.lastName = lastName
        self.phone = phone
        self.email = email
        self.address = address
    }

    /// The fields the form would store, or nil when the phone can't be read.
    /// A phone left exactly as the form showed it keeps the stored value,
    /// even an older one PhoneUtils can't parse.
    func proposedFields(original: ClientContactFields) -> ClientContactFields? {
        let phoneText = TextInputLimits.clamped(phone, to: TextInputLimits.phone)
        let proposedPhone: String?
        if phoneText.isEmpty {
            proposedPhone = nil
        } else if phoneText == ClientContactFields.formPhoneText(original.phone).trimmed {
            proposedPhone = original.phone
        } else if let e164 = PhoneUtils.toE164(phoneText) {
            proposedPhone = e164
        } else {
            return nil
        }

        let proposedAddress: String?
        if let address {
            proposedAddress = TextInputLimits.clampedOptional(address, to: TextInputLimits.address)
        } else {
            proposedAddress = original.address
        }

        return ClientContactFields(
            firstName: TextInputLimits.clamped(firstName, to: TextInputLimits.name),
            lastName: TextInputLimits.clamped(lastName, to: TextInputLimits.name),
            phone: proposedPhone,
            email: TextInputLimits.clampedOptional(email, to: TextInputLimits.email)?.lowercased(),
            address: proposedAddress
        )
    }
}

@MainActor
enum ClientEditSaver {
    enum Outcome: Equatable {
        case saved
        /// The form matches what it opened with; nothing was written.
        case unchanged
        /// Another device changed this client's details while the form was
        /// open. Nothing was written; ask before overwriting.
        case changedElsewhere
        case invalidPhone
        /// The client is no longer in the store (deleted on another device).
        case missing
        case failed(message: String)
    }

    /// Saves the fields the groomer changed. With `overwrite` false, a change
    /// saved on another device since `baseline` stops the save instead.
    ///
    /// The view's context doesn't merge another context's save  into an object it already holds, and saving that stale object
    /// puts every one of its old values back, not just the edited ones:
    /// another device's new phone, points or notes would be lost. So the
    /// view's object is re-read first and written only when the re-read
    /// matches the store; that keeps every screen showing this client in
    /// step. If it doesn't match (the view's object has unsaved changes, so
    /// a re-read can't refresh it), the write goes through a fresh context
    /// instead. That keeps this save from writing stale values, but the view's
    /// context still holds its stale object, and its own next save will put
    /// the old values back. Fixing that is outside this saver.
    static func save(
        _ form: ClientEditForm,
        baseline: ClientEditBaseline,
        container: ModelContainer,
        refreshing liveContext: ModelContext?,
        overwrite: Bool,
        currentDeviceID: UUID = DeviceIdentity.currentID
    ) -> Outcome {
        guard let proposed = form.proposedFields(original: baseline.fields) else {
            return .invalidPhone
        }
        let changed = proposed.changedFields(comparedTo: baseline.fields)
        guard !changed.isEmpty else { return .unchanged }

        let freshContext = ModelContext(container)
        guard let stored = fetchClient(baseline.clientUUID, in: freshContext) else {
            return .missing
        }
        let storedNow = ClientEditBaseline(stored)

        if !overwrite,
           baseline.hasChangeFromAnotherDevice(current: storedNow, currentDeviceID: currentDeviceID) {
            return .changedElsewhere
        }

        let target: Client
        let targetContext: ModelContext
        if let liveContext,
           let live = fetchClient(baseline.clientUUID, in: liveContext),
           ClientEditBaseline(live) == storedNow {
            target = live
            targetContext = liveContext
        } else {
            target = stored
            targetContext = freshContext
        }

        if changed.contains(.firstName) { target.setFirstName(proposed.firstName) }
        if changed.contains(.lastName) { target.setLastName(proposed.lastName) }
        if changed.contains(.phone) { target.setPhone(proposed.phone) }
        if changed.contains(.email) { target.setEmail(proposed.email) }
        if changed.contains(.address) { target.setAddress(proposed.address) }

        guard targetContext.hasChanges else { return .unchanged }
        do {
            try targetContext.save()
        } catch {
            Logger.clientEdit.error("Failed to save client edit: \(error.localizedDescription, privacy: .public)")
            Logger.database.error("Local save failed: \(error.localizedDescription, privacy: .public)")
            return .failed(message: error.localizedDescription)
        }
        if targetContext !== liveContext {
            refresh(baseline.clientUUID, in: liveContext)
        }
        return .saved
    }

    private static func fetchClient(_ clientUUID: UUID, in context: ModelContext) -> Client? {
        var descriptor = FetchDescriptor<Client>(predicate: #Predicate<Client> { $0.uuid == clientUUID })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// A fetch in the view's context re-reads the object it already holds,
    /// so the header shows the saved values. Read only.
    private static func refresh(_ clientUUID: UUID, in context: ModelContext?) {
        guard let context else { return }
        _ = fetchClient(clientUUID, in: context)
    }

    /// Re-reads `client` from the store before a form opens on it, so the
    /// form starts from what the store has rather than from values the
    /// view's context kept after another device's change. Read only; an
    /// object with unsaved edits keeps them.
    static func refresh(_ client: Client) {
        refresh(client.uuid, in: client.modelContext)
    }
}

private extension Logger {
    static let clientEdit = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "ClientEdit")
}
