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

            InsightsView()
                .tabItem { Label("Insights", systemImage: "chart.bar.fill") }
        }
    }
}

