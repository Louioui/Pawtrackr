
import SwiftUI

struct CoordinatorView: UIViewControllerRepresentable {
    @EnvironmentObject var appSettings: AppSettings
    @EnvironmentObject var authViewModel: AuthenticationViewModel

    func makeUIViewController(context: Context) -> UINavigationController {
        let navigationController = UINavigationController()
        let coordinator = MainCoordinator(navigationController: navigationController, appSettings: appSettings, authViewModel: authViewModel)
        coordinator.start()
        return navigationController
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
}
