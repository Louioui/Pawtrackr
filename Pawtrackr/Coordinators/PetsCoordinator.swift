
import SwiftUI

class PetsCoordinator: Coordinator {
    var navigationController: UINavigationController

    init(navigationController: UINavigationController) {
        self.navigationController = navigationController
    }

    func start() {
        // This coordinator is started by another coordinator, so this method is empty.
    }

    func showPetDetail(pet: Pet, namespace: Namespace.ID) {
        let petDetailView = PetDetailViewModel.PetDetailView(pet: pet, namespace: namespace)
        navigationController.pushViewController(UIHostingController(rootView: petDetailView), animated: true)
    }
}
