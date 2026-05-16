import SwiftUI

enum NavigationItem: String, CaseIterable, Identifiable, Hashable {
    case dashboard
    case clients
    case insights
    case settings

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dashboard:
            return NSLocalizedString("dashboard.title", value: "Dashboard", comment: "")
        case .clients:
            return NSLocalizedString("clients.tab", value: "Clients", comment: "")
        case .insights:
            return NSLocalizedString("insights.tab", value: "Insights", comment: "")
        case .settings:
            return NSLocalizedString("settings.tab", value: "Settings", comment: "")
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

    // iPad-specific bug: `NavigationLink(value:)` inside a sidebar
    // `List(selection:)` of a `NavigationSplitView` does not update the
    // selection binding on iPad — SwiftUI looks for a `NavigationStack`
    // to push the value onto, and the sidebar isn't inside one, so taps
    // fire but the binding never moves and the detail never changes.
    // macOS bridges this automatically; iPad does not.
    //
    // Plain `Label(...).tag(item)` rows make the row directly selectable
    // by the `List`'s selection binding, which is what drives
    // `splitViewDetail` to switch in the parent. Do NOT wrap the tag
    // value in `Optional(...)` — the bare value form is what works on
    // both iPad and macOS; wrapping in Optional broke macOS in a
    // previous attempt.
    var body: some View {
        List(selection: $selection) {
            Section(NSLocalizedString("sidebar.section.business", value: "Business", comment: "")) {
                Label(NavigationItem.dashboard.label, systemImage: NavigationItem.dashboard.icon)
                    .tag(NavigationItem.dashboard)
                    .accessibilityIdentifier("sidebar.row.dashboard")
                Label(NavigationItem.clients.label, systemImage: NavigationItem.clients.icon)
                    .tag(NavigationItem.clients)
                    .accessibilityIdentifier("sidebar.row.clients")
            }

            Section(NSLocalizedString("sidebar.section.analysis", value: "Analysis", comment: "")) {
                Label(NavigationItem.insights.label, systemImage: NavigationItem.insights.icon)
                    .tag(NavigationItem.insights)
                    .accessibilityIdentifier("sidebar.row.insights")
            }

            Section(NSLocalizedString("sidebar.section.system", value: "System", comment: "")) {
                Label(NavigationItem.settings.label, systemImage: NavigationItem.settings.icon)
                    .tag(NavigationItem.settings)
                    .accessibilityIdentifier("sidebar.row.settings")
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Pawtrackr")
    }
}
