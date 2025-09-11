//
//  MainTabView.swift
//  Pawtrackr
//
//  Primary tab scaffold for the app shell.
//

import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            ClientsView()
                .tabItem { Label("Clients", systemImage: "person.3.fill") }

            AppointmentsView()
                .tabItem { Label("Appointments", systemImage: "calendar") }

            ActiveSessionsView()
                .tabItem { Label("Active", systemImage: "hourglass") }

            InsightsView()
                .tabItem { Label("Insights", systemImage: "chart.bar.fill") }

            SettingsRootView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

// MARK: - Minimal placeholders (replace as features land)
private struct AppointmentsView: View {
    var body: some View {
        NavigationStack { Text("Appointments").navigationTitle("Appointments") }
    }
}

private struct ActiveSessionsView: View {
    var body: some View {
        NavigationStack { Text("Active Sessions").navigationTitle("Active Sessions") }
    }
}

private struct SettingsRootView: View {
    var body: some View {
        NavigationStack { Text("Settings").navigationTitle("Settings") }
    }
}

