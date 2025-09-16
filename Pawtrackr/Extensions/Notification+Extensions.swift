//
//  Notification+Extensions.swift
//  Pawtrackr
//
//  Centralized app-wide notification names and payload helpers.
//

import Foundation
import SwiftData

extension Notification.Name {
    /// Posted after a successful checkout so views (Clients, Pet Detail, Recent History, Insights) can refresh.
    static let visitDidComplete = Notification.Name("visitDidComplete")
}

// MARK: - Visit completion metadata

/// Envelope describing a completed visit that is attached to `.visitDidComplete` notifications.
///
/// This enables observers to perform targeted refreshes instead of always re-querying their
/// entire datasets. Only lightweight identifiers and summary strings are included so that the
/// payload remains cheap to construct and safe to pass across threads.
struct VisitDidCompleteMetadata: Sendable {
    enum Keys {
        static let visitPersistentID = "visitPersistentID"
        static let visitUUID = "visitUUID"
        static let petPersistentID = "petPersistentID"
        static let petUUID = "petUUID"
        static let clientPersistentID = "clientPersistentID"
        static let clientUUID = "clientUUID"
        static let endedAt = "endedAt"
        static let searchableText = "searchableText"
    }

    let visitPersistentID: PersistentIdentifier?
    let visitUUID: UUID?
    let petPersistentID: PersistentIdentifier?
    let petUUID: UUID?
    let clientPersistentID: PersistentIdentifier?
    let clientUUID: UUID?
    let endedAt: Date?
    /// Lowercased string containing searchable fields (pet, owner, services, notes, payment reference).
    let searchableText: String

    init(visit: Visit) {
        self.visitPersistentID = visit.persistentModelID
        self.visitUUID = visit.uuid
        self.petPersistentID = visit.pet.persistentModelID
        self.petUUID = visit.pet.uuid
        if let owner = visit.pet.owner {
            self.clientPersistentID = owner.persistentModelID
            self.clientUUID = owner.uuid
        } else {
            self.clientPersistentID = nil
            self.clientUUID = nil
        }
        self.endedAt = visit.endedAt ?? Date()

        let petName = visit.pet.name
        let ownerName = visit.pet.owner?.fullName ?? ""
        let services = visit.items.map { $0.name }.joined(separator: " ")
        let note = visit.note ?? ""
        let reference = visit.payment?.externalReference ?? ""
        let combined = [petName, ownerName, services, note, reference]
            .joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        self.searchableText = combined
    }

    init?(notification: Notification) {
        guard notification.name == .visitDidComplete else { return nil }
        let info = notification.userInfo ?? [:]
        self.visitPersistentID = info[Keys.visitPersistentID] as? PersistentIdentifier
        self.visitUUID = info[Keys.visitUUID] as? UUID
        self.petPersistentID = info[Keys.petPersistentID] as? PersistentIdentifier
        self.petUUID = info[Keys.petUUID] as? UUID
        self.clientPersistentID = info[Keys.clientPersistentID] as? PersistentIdentifier
        self.clientUUID = info[Keys.clientUUID] as? UUID
        self.endedAt = info[Keys.endedAt] as? Date
        if let text = info[Keys.searchableText] as? String, !text.isEmpty {
            self.searchableText = text
        } else {
            self.searchableText = ""
        }
    }

    var userInfo: [AnyHashable: Any] {
        var info: [AnyHashable: Any] = [:]
        if let visitPersistentID { info[Keys.visitPersistentID] = visitPersistentID }
        if let visitUUID { info[Keys.visitUUID] = visitUUID }
        if let petPersistentID { info[Keys.petPersistentID] = petPersistentID }
        if let petUUID { info[Keys.petUUID] = petUUID }
        if let clientPersistentID { info[Keys.clientPersistentID] = clientPersistentID }
        if let clientUUID { info[Keys.clientUUID] = clientUUID }
        if let endedAt { info[Keys.endedAt] = endedAt }
        if !searchableText.isEmpty { info[Keys.searchableText] = searchableText }
        return info
    }

    /// Determines if the payload contains enough information to evaluate a free-form search query.
    /// Empty queries always match.
    func matchesSearchQuery(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        guard !searchableText.isEmpty else { return false }
        let haystack = searchableText
        let tokens = trimmed
            .split(whereSeparator: { $0.isWhitespace })
            .map { token in
                token.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                    .lowercased()
            }
        return tokens.allSatisfy { haystack.contains($0) }
    }
}

extension NotificationCenter {
    /// Convenience helper to post a visit completion notification with the enriched payload.
    func postVisitDidComplete(metadata: VisitDidCompleteMetadata) {
        post(name: .visitDidComplete, object: nil, userInfo: metadata.userInfo)
    }
}

extension Notification {
    /// Extract the metadata payload if this notification represents a completed visit.
    var visitDidCompleteMetadata: VisitDidCompleteMetadata? {
        VisitDidCompleteMetadata(notification: self)
    }
}
