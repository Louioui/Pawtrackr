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
                .tabItem { Label("clients.tab", systemImage: "person.3.fill") }

            InsightsView()
                .tabItem { Label("insights.tab", systemImage: "chart.bar.fill") }
        }
    }
}
