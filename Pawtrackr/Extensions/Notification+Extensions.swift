//
//  Notification+Extensions.swift
//  Pawtrackr
//
//  Centralized app-wide notification names.
//

import Foundation
import SwiftData

extension Notification.Name {
    /// Posted after a successful checkout so views (Clients, Pet Detail, Recent History, Insights) can refresh.
    static let visitDidComplete = Notification.Name("visitDidComplete")
    /// Posted after a new client is created, for auto-navigation.
    static let clientDidCreate = Notification.Name("clientDidCreate")
    /// Request to open an existing client by ID (e.g., duplicate detected)
    static let clientOpenRequested = Notification.Name("clientOpenRequested")
    /// Request to select a top-level navigation surface.
    static let selectNavigationItem = Notification.Name("selectNavigationItem")
    /// Posted by CloudKitMonitor when sync state changes (idle/syncing/error/account).
    static let cloudKitStateDidChange = Notification.Name("cloudKitStateDidChange")
}

// Strongly-typed keys for .visitDidComplete userInfo payloads.
enum VisitDidCompleteKey: String {
    case visitID
    case petID
    case clientID
    case endedAt
    case total
}

extension Notification {
    var visitID: PersistentIdentifier? { userInfo?[VisitDidCompleteKey.visitID.rawValue] as? PersistentIdentifier }
    var petID: PersistentIdentifier? { userInfo?[VisitDidCompleteKey.petID.rawValue] as? PersistentIdentifier }
    var clientID: PersistentIdentifier? { userInfo?[VisitDidCompleteKey.clientID.rawValue] as? PersistentIdentifier }
    var endedAtDate: Date? { userInfo?[VisitDidCompleteKey.endedAt.rawValue] as? Date }
    var totalAmount: Decimal? { userInfo?[VisitDidCompleteKey.total.rawValue] as? Decimal }
}

// Client creation payload
enum ClientDidCreateKey: String { case clientID, phase }

enum ClientDidCreatePhase: String { case created, navigated }

extension Notification {
    var createdClientID: PersistentIdentifier? { userInfo?[ClientDidCreateKey.clientID.rawValue] as? PersistentIdentifier }
    var clientCreatePhase: ClientDidCreatePhase? {
        guard let raw = userInfo?[ClientDidCreateKey.phase.rawValue] as? String else { return nil }
        return ClientDidCreatePhase(rawValue: raw)
    }
}

// Open existing client payload
enum ClientOpenKey: String { case clientID }

extension Notification {
    var requestedClientID: PersistentIdentifier? { userInfo?[ClientOpenKey.clientID.rawValue] as? PersistentIdentifier }
}

// Top-level navigation selection payload
enum NavigationSelectionKey: String { case item, resetPath }

extension Notification {
    var requestedNavigationItem: NavigationItem? {
        guard let rawValue = userInfo?[NavigationSelectionKey.item.rawValue] as? String else { return nil }
        return NavigationItem(rawValue: rawValue)
    }

    var shouldResetNavigationPath: Bool {
        userInfo?[NavigationSelectionKey.resetPath.rawValue] as? Bool ?? false
    }
}
