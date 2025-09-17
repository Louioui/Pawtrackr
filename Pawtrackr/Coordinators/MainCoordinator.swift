
import SwiftUI

class MainCoordinator: Coordinator {
    var navigationController: UINavigationController
    var appSettings: AppSettings
    var authViewModel: AuthenticationViewModel

    init(navigationController: UINavigationController, appSettings: AppSettings, authViewModel: AuthenticationViewModel) {
        self.navigationController = navigationController
        self.appSettings = appSettings
        self.authViewModel = authViewModel
    }

    func start() {
        let mainTabView = MainTabView()
            .environmentObject(appSettings)
            .environmentObject(authViewModel)
        navigationController.pushViewController(UIHostingController(rootView: mainTabView), animated: false)
    }
}
