//
//  CoordinatorView.swift
//  Pawtrackr
//
//  Legacy coordinator view - iOS only.
//  Navigation is now handled by ContentView for cross-platform support.
//

#if canImport(UIKit)
import SwiftUI
import SwiftData
import UIKit

struct CoordinatorView: UIViewControllerRepresentable {
    @EnvironmentObject var appSettings: AppSettings
    @EnvironmentObject var authViewModel: AuthenticationViewModel
    @Environment(\.modelContext) private var modelContext

    final class Holder {
        var mainCoordinator: MainCoordinator?
    }

    func makeCoordinator() -> Holder {
        Holder()
    }

    func makeUIViewController(context: Context) -> UINavigationController {
        let navigationController = UINavigationController()
        let coordinator = MainCoordinator(
            navigationController: navigationController,
            appSettings: appSettings,
            authViewModel: authViewModel,
            modelContext: modelContext
        )
        context.coordinator.mainCoordinator = coordinator
        coordinator.start()
        return navigationController
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
}
#endif
