import SwiftUI

enum NavigationItem: String, CaseIterable, Identifiable {
    case dashboard
    case clients
    case insights
    case settings

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .clients: return "Clients"
        case .insights: return "Insights"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: return "square.grid.2x2.fill"
        case .clients: return "person.3.fill"
        case .insights: return "chart.bar.fill"
        case .settings: return "gear"
        }
    }
}

struct SidebarView: View {
    @Binding var selection: NavigationItem?

    var body: some View {
        List(selection: $selection) {
            Section("Business") {
                NavigationLink(value: NavigationItem.dashboard) {
                    Label(NavigationItem.dashboard.label, systemImage: NavigationItem.dashboard.icon)
                }
                NavigationLink(value: NavigationItem.clients) {
                    Label(NavigationItem.clients.label, systemImage: NavigationItem.clients.icon)
                }
            }

            Section("Analysis") {
                NavigationLink(value: NavigationItem.insights) {
                    Label(NavigationItem.insights.label, systemImage: NavigationItem.insights.icon)
                }
            }

            Section("System") {
                NavigationLink(value: NavigationItem.settings) {
                    Label(NavigationItem.settings.label, systemImage: NavigationItem.settings.icon)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Pawtrackr")
    }
}
