import SwiftUI

enum NavigationItem: String, CaseIterable, Identifiable {
    case clients
    case insights
    case settings
    
    var id: String { rawValue }
    
    var label: String {
        switch self {
        case .clients: return "Clients"
        case .insights: return "Insights"
        case .settings: return "Settings"
        }
    }
    
    var icon: String {
        switch self {
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
            ForEach(NavigationItem.allCases) { item in
                NavigationLink(value: item) {
                    Label(item.label, systemImage: item.icon)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Pawtrackr")
    }
}
