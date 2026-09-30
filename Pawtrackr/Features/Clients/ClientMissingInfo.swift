//
//  ClientMissingInfo.swift
//  Pawtrackr
//
//  What a client's record still lacks: an emergency contact, the owner's
//  phone, the owner's email. One rule for the Missing Info filter, the
//  client card's chip and the "Missing:" note on the client's profile, so
//  a client the profile flags is always in the filter, and the other way
//  around. Blank text counts as missing.
//

import Foundation

enum ClientMissingInfo: CaseIterable, Equatable, Sendable {
    case emergencyContact
    case ownerPhone
    case ownerEmail

    var title: String {
        switch self {
        case .emergencyContact:
            return AppLocalization.localized("client_detail.missing.emergency_contact", value: "Emergency contact")
        case .ownerPhone:
            return AppLocalization.localized("client_detail.missing.owner_phone", value: "Owner phone")
        case .ownerEmail:
            return AppLocalization.localized("client_detail.missing.owner_email", value: "Owner email")
        }
    }

    static func items(hasEmergencyContact: Bool, phone: String?, email: String?) -> [ClientMissingInfo] {
        var items: [ClientMissingInfo] = []
        if !hasEmergencyContact { items.append(.emergencyContact) }
        if isBlank(phone) { items.append(.ownerPhone) }
        if isBlank(email) { items.append(.ownerEmail) }
        return items
    }

    static func items(for client: Client) -> [ClientMissingInfo] {
        items(
            hasEmergencyContact: !(client.emergencyContacts ?? []).isEmpty,
            phone: client.phone,
            email: client.email
        )
    }

    static func isIncomplete(_ client: Client) -> Bool {
        !items(for: client).isEmpty
    }

    /// "Missing: Emergency contact and Owner email", or nil when nothing is.
    static func summary(_ items: [ClientMissingInfo]) -> String? {
        guard !items.isEmpty else { return nil }
        let titles = items.map(\.title)
        let formatter = ListFormatter()
        formatter.locale = AppLocalization.currentLocale
        let list = formatter.string(from: titles) ?? titles.joined(separator: ", ")
        return String(format: AppLocalization.localized("client_detail.missing_fmt", value: "Missing: %@"), list)
    }

    private static func isBlank(_ value: String?) -> Bool {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
