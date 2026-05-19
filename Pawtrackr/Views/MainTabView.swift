import SwiftUI

/// Legacy MainTabView - now deprecated in favor of ContentView.
/// Kept for backward compatibility with any remaining references.
struct MainTabView: View {
    @Environment(AppSettings.self) private var appSettings
    @Environment(AuthenticationViewModel.self) private var authViewModel
    @Namespace var sharedNamespace

    var body: some View {
        TabView {
            ClientsView(namespace: sharedNamespace)
                .tabItem {
                    Label(NSLocalizedString("clients.tab", value: "Clients", comment: ""), systemImage: "person.3.fill")
                }

            InsightsView()
                .tabItem {
                    Label(NSLocalizedString("insights.tab", value: "Insights", comment: ""), systemImage: "chart.bar.fill")
                }

            SettingsView()
                .tabItem {
                    Label(NSLocalizedString("settings.tab", value: "Settings", comment: ""), systemImage: "gear")
                }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }
}
