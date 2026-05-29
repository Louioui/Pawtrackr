import SwiftUI
import SwiftData

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
    @Query(sort: \DeviceMetadata.lastSyncAt, order: .reverse) private var devices: [DeviceMetadata]
    var onSelect: (NavigationItem) -> Void = { _ in }

    var body: some View {
        List {
            Section(NSLocalizedString("sidebar.section.business", value: "Business", comment: "")) {
                SidebarRow(item: .dashboard, selection: $selection, onSelect: onSelect)
                SidebarRow(item: .clients, selection: $selection, onSelect: onSelect)
            }

            Section(NSLocalizedString("sidebar.section.analysis", value: "Analysis", comment: "")) {
                SidebarRow(item: .insights, selection: $selection, onSelect: onSelect)
            }

            #if os(macOS)
            if !devices.isEmpty {
                Section("Worker Devices") {
                    ForEach(devices.prefix(5)) { device in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.name)
                                    .font(.caption.weight(.medium))
                                Text(device.lastSyncAt.formatted(.relative(presentation: .numeric)))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Circle()
                                .fill(isOnline(device) ? .green : .secondary)
                                .frame(width: 8, height: 8)
                        }
                    }
                }
            }
            #endif

            Section(NSLocalizedString("sidebar.section.system", value: "System", comment: "")) {
                SidebarRow(item: .settings, selection: $selection, onSelect: onSelect)
            }
        }
        .listStyle(.sidebar)
        .glassmorphicSidebar()
        .navigationTitle("Pawtrackr")
    }
    
    private func isOnline(_ device: DeviceMetadata) -> Bool {
        // Consider a device "online" if it synced in the last 10 minutes
        Date().timeIntervalSince(device.lastSyncAt) < 600
    }
}

private struct SidebarRow: View {
    let item: NavigationItem
    @Binding var selection: NavigationItem?
    let onSelect: (NavigationItem) -> Void
    @State private var isHovering = false

    var body: some View {
        Button {
            selection = item
            onSelect(item)
        } label: {
            Label(item.label, systemImage: item.icon)
                .font(.body.weight(selection == item ? .semibold : .regular))
                .foregroundStyle(selection == item ? Color.accentColor : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                #if os(macOS)
                .scaleEffect(isHovering ? 1.02 : 1.0)
                .shadow(color: isHovering ? .black.opacity(0.08) : .clear, radius: 4, y: 2)
                .animation(.spring(response: 0.32, dampingFraction: 0.72), value: isHovering)
                #endif
        }
        .buttonStyle(.plain)
        .listRowBackground(selection == item ? Color.accentColor.opacity(0.14) : Color.clear)
        .accessibilityIdentifier("sidebar.row.\(item.rawValue)")
        .accessibilityAddTraits(selection == item ? .isSelected : [])
        #if os(macOS)
        .onHover { hovering in isHovering = hovering }
        #endif
    }
}
