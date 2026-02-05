//
//  MainCoordinator.swift
//  Pawtrackr
//
//  Legacy coordinator - iOS only.
//  Navigation is now handled by NavigationRouter for cross-platform support.
//

#if canImport(UIKit)
import SwiftUI
import SwiftData
import UIKit

class MainCoordinator: Coordinator {
    var navigationController: UINavigationController
    var appSettings: AppSettings
    var authViewModel: AuthenticationViewModel
    private let modelContext: ModelContext

    init(navigationController: UINavigationController, appSettings: AppSettings, authViewModel: AuthenticationViewModel, modelContext: ModelContext) {
        self.navigationController = navigationController
        self.appSettings = appSettings
        self.authViewModel = authViewModel
        self.modelContext = modelContext
    }

    func start() {
        let clientsCoordinator = ClientsCoordinator(navigationController: navigationController)
        let mainTabView = MainTabView()
            .environmentObject(appSettings)
            .environmentObject(authViewModel)
            .environment(\.modelContext, modelContext)
        navigationController.pushViewController(UIHostingController(rootView: mainTabView), animated: false)
    }
}
#endif
