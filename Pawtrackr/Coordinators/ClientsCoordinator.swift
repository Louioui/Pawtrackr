
import SwiftUI

class ClientsCoordinator: Coordinator {
    var navigationController: UINavigationController

    init(navigationController: UINavigationController) {
        self.navigationController = navigationController
    }

    func start() {
        let clientsView = ClientsView(coordinator: self)
        navigationController.pushViewController(UIHostingController(rootView: clientsView), animated: false)
    }

    @MainActor
    func showClientDetail(client: Client, namespace: Namespace.ID) {
        let clientDetailView = ClientDetailView(client: client, coordinator: self, namespace: namespace)
        navigationController.pushViewController(UIHostingController(rootView: clientDetailView), animated: true)
    }

    func showVisitDetail(visit: Visit) {
        let visitDetailView = VisitDetailView(visit: visit)
        navigationController.pushViewController(UIHostingController(rootView: visitDetailView), animated: true)
    }
}
