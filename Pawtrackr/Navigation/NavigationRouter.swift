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

// MARK: - NavigationRouter

/// Observable router that manages navigation state across the app.
/// Uses NavigationPath for programmatic navigation with NavigationStack.
@Observable
@MainActor
final class NavigationRouter {

    /// Navigation path for the Clients tab
    var clientsPath = NavigationPath()

    /// Navigation path for the Insights tab (if needed)
    var insightsPath = NavigationPath()

    /// Navigation path for the Settings tab (if needed)
    var settingsPath = NavigationPath()

    // MARK: - Navigation Actions

    func navigateToClient(_ client: Client) {
        clientsPath.append(AppDestination.clientDetail(client))
    }

    func navigateToPet(_ pet: Pet) {
        clientsPath.append(AppDestination.petDetail(pet))
    }

    func navigateToVisit(_ visit: Visit) {
        clientsPath.append(AppDestination.visitDetail(visit))
    }

    func navigateToPetHistory(_ pet: Pet) {
        clientsPath.append(AppDestination.petHistory(pet))
    }

    func navigateToCheckout(_ pet: Pet) {
        clientsPath.append(AppDestination.checkout(pet))
    }

    func pop() {
        if !clientsPath.isEmpty {
            clientsPath.removeLast()
        }
    }

    func popToRoot() {
        clientsPath = NavigationPath()
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
