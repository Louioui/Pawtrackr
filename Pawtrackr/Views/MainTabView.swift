import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var appSettings: AppSettings
    @EnvironmentObject var authViewModel: AuthenticationViewModel

    var body: some View {
        TabView {
            ClientsView(coordinator: ClientsCoordinator(navigationController: UINavigationController())) // Placeholder coordinator
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