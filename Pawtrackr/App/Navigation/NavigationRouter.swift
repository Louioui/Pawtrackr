//
//  NavigationRouter.swift
//  Pawtrackr
//
//  Cross-platform navigation router using SwiftUI NavigationStack.
//  Replaces UIKit-based Coordinator pattern for iOS/macOS compatibility.
//

import SwiftUI
import SwiftData
import OSLog

// MARK: - Navigation Destinations

/// Type-safe navigation destinations for the app.
enum AppDestination: Hashable, Sendable {
    case clientDetail(PersistentIdentifier)
    case petDetail(PersistentIdentifier)
    case visitDetail(PersistentIdentifier)
    case petHistory(PersistentIdentifier)
    case checkout(petID: PersistentIdentifier, visitID: PersistentIdentifier?)
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
        append(AppDestination.clientDetail(client.persistentModelID))
    }

    func navigateToPet(_ pet: Pet) {
        append(AppDestination.petDetail(pet.persistentModelID))
    }

    func navigateToVisit(_ visit: Visit) {
        append(AppDestination.visitDetail(visit.persistentModelID))
    }

    func navigateToPetHistory(_ pet: Pet) {
        append(AppDestination.petHistory(pet.persistentModelID))
    }

    func navigateToCheckout(_ pet: Pet) {
        append(AppDestination.checkout(petID: pet.persistentModelID, visitID: nil))
    }

    func navigateToCheckout(_ visit: Visit) {
        guard let pet = visit.pet else {
            Logger.database.error("Cannot route checkout: visit \(visit.uuid.uuidString, privacy: .public) has no pet relationship")
            return
        }
        append(AppDestination.checkout(petID: pet.persistentModelID, visitID: visit.persistentModelID))
    }

    func pop() {
        switch activeNavigationItem {
        case .dashboard:
            guard !dashboardPath.isEmpty else { return }
            var path = dashboardPath
            path.removeLast()
            dashboardPath = path
        case .clients:
            guard !clientsPath.isEmpty else { return }
            var path = clientsPath
            path.removeLast()
            clientsPath = path
        case .insights:
            guard !insightsPath.isEmpty else { return }
            var path = insightsPath
            path.removeLast()
            insightsPath = path
        case .settings:
            guard !settingsPath.isEmpty else { return }
            var path = settingsPath
            path.removeLast()
            settingsPath = path
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
            var path = dashboardPath
            path.append(destination)
            dashboardPath = path
        case .clients:
            var path = clientsPath
            path.append(destination)
            clientsPath = path
        case .insights:
            var path = insightsPath
            path.append(destination)
            insightsPath = path
        case .settings:
            var path = settingsPath
            path.append(destination)
            settingsPath = path
        }
    }
}

enum CheckoutRouteResolver {
    @MainActor
    static func activeVisitID(
        for petID: PersistentIdentifier,
        preferredVisitID: PersistentIdentifier?,
        dataStore: DataStoreService
    ) throws -> PersistentIdentifier? {
        try dataStore.resolveActiveCheckoutVisitID(for: petID, preferredVisitID: preferredVisitID)
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
