//
//  Notification+Extensions.swift
//  Pawtrackr
//
//  Centralized app-wide notification names and strongly-typed payload helpers.
//

import Foundation
import SwiftData

extension Notification.Name {
    /// Posted after a successful checkout so views (Clients, Pet Detail, Recent History, Insights) can refresh.
    static let visitDidComplete = Notification.Name("visitDidComplete")
}

/// Namespace describing the metadata carried with the `.visitDidComplete` notification.
enum VisitDidCompleteNotification {
    /// Strongly-typed payload so observers can refresh only the data they care about.
    struct Payload: Sendable, Equatable {
        let visitID: PersistentIdentifier?
        let visitUUID: UUID?
        let petID: PersistentIdentifier?
        let clientID: PersistentIdentifier?
        let endedAt: Date?

        init(
            visitID: PersistentIdentifier? = nil,
            visitUUID: UUID? = nil,
            petID: PersistentIdentifier? = nil,
            clientID: PersistentIdentifier? = nil,
            endedAt: Date? = nil
        ) {
            self.visitID = visitID
            self.visitUUID = visitUUID
            self.petID = petID
            self.clientID = clientID
            self.endedAt = endedAt
        }

        init(visit: Visit) {
            self.visitID = visit.persistentModelID
            self.visitUUID = visit.uuid
            self.petID = visit.pet.persistentModelID
            self.clientID = visit.pet.owner?.persistentModelID
            self.endedAt = visit.endedAt ?? visit.startedAt
        }

        fileprivate enum Key: String {
            case visitID
            case visitUUID
            case petID
            case clientID
            case endedAt
        }

        fileprivate var userInfo: [AnyHashable: Any] {
            var info: [AnyHashable: Any] = [:]
            if let visitID { info[Key.visitID.rawValue] = visitID }
            if let visitUUID { info[Key.visitUUID.rawValue] = visitUUID }
            if let petID { info[Key.petID.rawValue] = petID }
            if let clientID { info[Key.clientID.rawValue] = clientID }
            if let endedAt { info[Key.endedAt.rawValue] = endedAt }
            return info
        }
    }
}

extension NotificationCenter {
    /// Convenience helper to post the visit completion notification with typed metadata.
    func postVisitDidComplete(payload: VisitDidCompleteNotification.Payload) {
        post(name: .visitDidComplete, object: nil, userInfo: payload.userInfo)
    }
}

extension Notification {
    /// Attempts to deserialize the `.visitDidComplete` payload for targeted refreshes.
    var visitDidCompletePayload: VisitDidCompleteNotification.Payload? {
        guard name == .visitDidComplete else { return nil }

        if let visit = object as? Visit {
            return VisitDidCompleteNotification.Payload(visit: visit)
        }

        guard let userInfo else { return nil }

        let visitID = userInfo[VisitDidCompleteNotification.Payload.Key.visitID.rawValue] as? PersistentIdentifier
        let visitUUID = userInfo[VisitDidCompleteNotification.Payload.Key.visitUUID.rawValue] as? UUID
        let petID = userInfo[VisitDidCompleteNotification.Payload.Key.petID.rawValue] as? PersistentIdentifier
        let clientID = userInfo[VisitDidCompleteNotification.Payload.Key.clientID.rawValue] as? PersistentIdentifier
        let endedAt = userInfo[VisitDidCompleteNotification.Payload.Key.endedAt.rawValue] as? Date

        if visitID == nil && visitUUID == nil && petID == nil && clientID == nil && endedAt == nil {
            return nil
        }

        return VisitDidCompleteNotification.Payload(
            visitID: visitID,
            visitUUID: visitUUID,
            petID: petID,
            clientID: clientID,
            endedAt: endedAt
        )
    }
}
