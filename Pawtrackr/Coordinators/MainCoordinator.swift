
import SwiftUI

class MainCoordinator: Coordinator {
    var navigationController: UINavigationController

    init(navigationController: UINavigationController) {
        self.navigationController = navigationController
    }

    func start() {
        let clientsCoordinator = ClientsCoordinator(navigationController: navigationController)
        clientsCoordinator.start()
    }
}
