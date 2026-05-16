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
    var onSelect: (NavigationItem) -> Void = { _ in }

    var body: some View {
        List {
            Section(NSLocalizedString("sidebar.section.business", value: "Business", comment: "")) {
                sidebarButton(.dashboard)
                sidebarButton(.clients)
            }

            Section(NSLocalizedString("sidebar.section.analysis", value: "Analysis", comment: "")) {
                sidebarButton(.insights)
            }

            Section(NSLocalizedString("sidebar.section.system", value: "System", comment: "")) {
                sidebarButton(.settings)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Pawtrackr")
    }

    private func sidebarButton(_ item: NavigationItem) -> some View {
        Button {
            selection = item
            onSelect(item)
        } label: {
            Label(item.label, systemImage: item.icon)
                .font(.body.weight(selection == item ? .semibold : .regular))
                .foregroundStyle(selection == item ? Color.accentColor : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(selection == item ? Color.accentColor.opacity(0.14) : Color.clear)
        .accessibilityIdentifier("sidebar.row.\(item.rawValue)")
        .accessibilityAddTraits(selection == item ? .isSelected : [])
    }
}
