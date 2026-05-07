//
//  NavigationRouter.swift
//  Pawtrackr
//
//  Cross-platform navigation router using SwiftUI NavigationStack.
//  Replaces UIKit-based Coordinator pattern for iOS/macOS compatibility.
//

import SwiftUI
import SwiftData

// MARK: - Navigation Destinations

/// Type-safe navigation destinations for the app.
enum AppDestination: Hashable {
    case clientDetail(Client)
    case petDetail(Pet)
    case visitDetail(Visit)
    case petHistory(Pet)
    case checkout(Pet)
}

enum PendingNavigationCommand {
    enum Kind: String {
        case client
        case pet
    }

    static let kindKey = "pendingNavigationKind"
    static let uuidKey = "pendingNavigationUUID"
}

// MARK: - NavigationRouter

/// Observable router that manages navigation state across the app.
/// Uses NavigationPath for programmatic navigation with NavigationStack.
@Observable
@MainActor
final class NavigationRouter {

    /// Navigation path for the Clients tab
    var clientsPath = NavigationPath()

    /// Navigation path for the Dashboard tab
    var dashboardPath = NavigationPath()

    /// Navigation path for the Insights tab (if needed)
    var insightsPath = NavigationPath()

    /// Navigation path for the Settings tab (if needed)
    var settingsPath = NavigationPath()

    /// The surface currently hosting user-driven navigation.
    var activeNavigationItem: NavigationItem = .dashboard

    // MARK: - Navigation Actions

    func navigateToClient(_ client: Client) {
        append(AppDestination.clientDetail(client))
    }

    func navigateToPet(_ pet: Pet) {
        append(AppDestination.petDetail(pet))
    }

    func navigateToVisit(_ visit: Visit) {
        append(AppDestination.visitDetail(visit))
    }

    func navigateToPetHistory(_ pet: Pet) {
        append(AppDestination.petHistory(pet))
    }

    func navigateToCheckout(_ pet: Pet) {
        append(AppDestination.checkout(pet))
    }

    func pop() {
        switch activeNavigationItem {
        case .dashboard:
            if !dashboardPath.isEmpty { dashboardPath.removeLast() }
        case .clients:
            if !clientsPath.isEmpty { clientsPath.removeLast() }
        case .insights:
            if !insightsPath.isEmpty { insightsPath.removeLast() }
        case .settings:
            if !settingsPath.isEmpty { settingsPath.removeLast() }
        }
    }

    func popToRoot() {
        switch activeNavigationItem {
        case .dashboard:
            dashboardPath = NavigationPath()
        case .clients:
            clientsPath = NavigationPath()
        case .insights:
            insightsPath = NavigationPath()
        case .settings:
            settingsPath = NavigationPath()
        }
    }

    func popDashboardToRoot() {
        dashboardPath = NavigationPath()
    }

    func popClientsToRoot() {
        clientsPath = NavigationPath()
    }

    private func append(_ destination: AppDestination) {
        switch activeNavigationItem {
        case .dashboard:
            dashboardPath.append(destination)
        case .clients:
            clientsPath.append(destination)
        case .insights:
            insightsPath.append(destination)
        case .settings:
            settingsPath.append(destination)
        }
    }
}

// MARK: - Model Hashable Conformance

/// Make SwiftData models Hashable for use with NavigationPath.
/// Uses uuid for identity since these are reference types.

extension Client: Hashable {
    static func == (lhs: Client, rhs: Client) -> Bool {
        lhs.uuid == rhs.uuid
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(uuid)
    }
}

extension Pet: Hashable {
    static func == (lhs: Pet, rhs: Pet) -> Bool {
        lhs.uuid == rhs.uuid
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(uuid)
    }
}

extension Visit: Hashable {
    static func == (lhs: Visit, rhs: Visit) -> Bool {
        lhs.uuid == rhs.uuid
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(uuid)
    }
}
