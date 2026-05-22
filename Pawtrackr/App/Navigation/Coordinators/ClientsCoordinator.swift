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
        // Legacy coordinator doesn't support shared namespace transitions.
        // Using @Namespace locally as a fallback.
        struct DummyClientsView: View {
            @Namespace var dummy
            var body: some View { ClientsView(namespace: dummy) }
        }
        navigationController.pushViewController(UIHostingController(rootView: DummyClientsView()), animated: false)
    }

    @MainActor
    func showClientDetail(client: Client) {
        struct DummyWrapper: View {
            let client: Client
            @Namespace var dummy
            var body: some View { ClientDetailView(client: client, namespace: dummy) }
        }
        navigationController.pushViewController(UIHostingController(rootView: DummyWrapper(client: client)), animated: true)
    }

    func showVisitDetail(visit: Visit) {
        let visitDetailView = VisitDetailView(visit: visit)
        navigationController.pushViewController(UIHostingController(rootView: visitDetailView), animated: true)
    }
}
#endif
