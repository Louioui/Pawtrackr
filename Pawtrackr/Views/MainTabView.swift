import SwiftUI

/// Legacy MainTabView - now deprecated in favor of ContentView.
/// Kept for backward compatibility with any remaining references.
struct MainTabView: View {
    @EnvironmentObject var appSettings: AppSettings
    @EnvironmentObject var authViewModel: AuthenticationViewModel

    var body: some View {
        TabView {
            ClientsView()
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
