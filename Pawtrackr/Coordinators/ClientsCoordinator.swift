//
//  ClientsCoordinator.swift
//  Pawtrackr
//
//  Legacy coordinator - iOS only.
//  Navigation is now handled by NavigationRouter for cross-platform support.
//

#if canImport(UIKit)
import SwiftUI
import UIKit

class ClientsCoordinator: Coordinator {
    var navigationController: UINavigationController

    init(navigationController: UINavigationController) {
        self.navigationController = navigationController
    }

    func start() {
        let clientsView = ClientsView()
        navigationController.pushViewController(UIHostingController(rootView: clientsView), animated: false)
    }

    @MainActor
    func showClientDetail(client: Client, namespace: Namespace.ID) {
        let clientDetailView = ClientDetailView(client: client)
        navigationController.pushViewController(UIHostingController(rootView: clientDetailView), animated: true)
    }

    func showVisitDetail(visit: Visit) {
        let visitDetailView = VisitDetailView(visit: visit)
        navigationController.pushViewController(UIHostingController(rootView: visitDetailView), animated: true)
    }
}
#endif
