//
//  PetsCoordinator.swift
//  Pawtrackr
//
//  Legacy coordinator - iOS only.
//  Navigation is now handled by NavigationRouter for cross-platform support.
//

#if canImport(UIKit)
import SwiftUI
import UIKit

class PetsCoordinator: Coordinator {
    var navigationController: UINavigationController

    init(navigationController: UINavigationController) {
        self.navigationController = navigationController
    }

    func start() {
        // This coordinator is started by another coordinator, so this method is empty.
    }

    func showPetDetail(pet: Pet, namespace: Namespace.ID) {
        let petDetailView = PetDetailView(pet: pet, namespace: namespace)
        navigationController.pushViewController(UIHostingController(rootView: petDetailView), animated: true)
    }
}
#endif
