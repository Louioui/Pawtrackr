//
//  EmergencyContactRules.swift
//  Pawtrackr
//
//  How a typed emergency contact becomes a stored one. New Client and the
//  contact editor in Client Details both use these rules, so a contact the
//  groomer typed is either saved or stops Save with a message on the field.
//  It is never dropped without a word (the old New Client mapping skipped
//  any contact whose phone wasn't a US number, and the client saved with no
//  contact at all).
//

import Foundation

enum EmergencyContactRules {
    enum Field: Hashable, Sendable {
        case name
        case phone
    }

    enum Outcome: Equatable, Sendable {
        /// Name and phone are both empty: an unused row, ignored.
        case blank
        /// Ready to store. `storedPhone` is E.164, or "" when no phone was typed.
        case valid(storedPhone: String)
        /// Save has to wait until the groomer fixes this field.
        case invalid(Field, message: String)
    }

    /// The phone is validated the same way as the client's own phone: a
    /// number PhoneUtils can't read blocks Save instead of being stored as
    /// text nothing can dial.
    static func evaluate(name: String, phone: String) -> Outcome {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedName.isEmpty && trimmedPhone.isEmpty {
            return .blank
        }
        if trimmedName.isEmpty {
            return .invalid(.name, message: nameRequiredMessage)
        }
        if trimmedPhone.isEmpty {
            return .valid(storedPhone: "")
        }
        guard let e164 = PhoneUtils.toE164(trimmedPhone) else {
            return .invalid(.phone, message: phoneInvalidMessage)
        }
        return .valid(storedPhone: e164)
    }

    static var nameRequiredMessage: String {
        AppLocalization.localized(
            "emergency_contact.validation.name_required",
            value: "Add a name for this contact, or clear the phone number."
        )
    }

    /// The contact editor has no empty rows to skip: Save with no name
    /// asks for one.
    static var nameMissingMessage: String {
        AppLocalization.localized(
            "emergency_contact.validation.name_missing",
            value: "Add a name for this contact."
        )
    }

    static var phoneInvalidMessage: String {
        AppLocalization.localized(
            "emergency_contact.validation.phone_invalid",
            value: "Enter a valid phone number, or leave it blank to save the name only."
        )
    }

    /// "Maria (sister) · (555) 123-4567". Parts that are empty are left out.
    static func summaryLine(name: String, relation: String?, phone: String) -> String {
        var line = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let relation = relation?.trimmingCharacters(in: .whitespacesAndNewlines), !relation.isEmpty {
            line += " (\(relation))"
        }
        let displayPhone = displayPhone(phone)
        if !displayPhone.isEmpty {
            line += " · \(displayPhone)"
        }
        return line
    }

    /// Formatted for reading. A stored value PhoneUtils can't format (older
    /// data, or a number typed before these rules) is shown as stored.
    static func displayPhone(_ phone: String) -> String {
        let trimmed = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return PhoneUtils.display(trimmed) ?? trimmed
    }
}
