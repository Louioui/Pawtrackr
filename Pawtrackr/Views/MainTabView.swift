//
//  MainTabView.swift
//  Pawtrackr
//
//  Primary tab scaffold for the app shell.
//

import SwiftUI

struct MainTabView: View {
    private let clientsCoordinator: ClientsCoordinator

    init() {
        clientsCoordinator = ClientsCoordinator(navigationController: UINavigationController())
    }

    var body: some View {
        TabView {
            ClientsView(coordinator: clientsCoordinator)
                .tabItem { Label("clients.tab", systemImage: "person.3.fill") }

            InsightsView()
                .tabItem { Label("insights.tab", systemImage: "chart.bar.fill") }

            SettingsView()
                .tabItem { Label("settings.tab", systemImage: "gear") }
        }
    }
}
