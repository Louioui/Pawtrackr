import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct MainTabView: View {
    @EnvironmentObject var appSettings: AppSettings
    @EnvironmentObject var authViewModel: AuthenticationViewModel
    private let clientsCoordinator: ClientsCoordinator

    init(clientsCoordinator: ClientsCoordinator) {
        self.clientsCoordinator = clientsCoordinator
    }

    // Convenience for call sites that don't have a navigation controller (e.g., RootView previews).
    // Note: This creates an internal UINavigationController and will not support navigation pushes the same way.
    // The app path uses MainCoordinator to inject the real controller.
    init() {
        #if canImport(UIKit)
        self.clientsCoordinator = ClientsCoordinator(navigationController: UINavigationController())
        #else
        // Fallback stub; this app targets iOS so this path shouldn't execute.
        self.clientsCoordinator = ClientsCoordinator(navigationController: UINavigationController())
        #endif
    }

    var body: some View {
        TabView {
            ClientsView(coordinator: clientsCoordinator)
                .tabItem {
                    Label("Clients", systemImage: "person.3.fill")
                }

            InsightsView()
                .tabItem {
                    Label("Insights", systemImage: "chart.bar.fill")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
    }
}
