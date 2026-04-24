//
//  ContentView.swift
//  Pawtrackr
//
//  Cross-platform main content view.
//  Uses NavigationSplitView for macOS/iPad and TabView for iPhone.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var appSettings: AppSettings
    @EnvironmentObject var authViewModel: AuthenticationViewModel

    @State private var router = NavigationRouter()
    @State private var sidebarSelection: NavigationItem? = .clients
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        rootContent
            .environment(router)
            .onChange(of: appSettings.currencySymbol) { _, newValue in
                Formatters.updateCurrencySymbol(newValue)
            }
    }

    // MARK: - Views

    @ViewBuilder
    private var rootContent: some View {
        #if os(macOS)
        splitView
        #else
        if horizontalSizeClass == .compact {
            tabView
        } else {
            splitView
        }
        #endif
    }

    private var tabView: some View {
        TabView {
            NavigationStack(path: $router.clientsPath) {
                ClientsView()
                    .navigationDestination(for: AppDestination.self) { destination in
                        destinationView(for: destination)
                    }
            }
            .tabItem { Label("Clients", systemImage: "person.3.fill") }

            NavigationStack(path: $router.insightsPath) {
                InsightsView()
            }
            .tabItem { Label("Insights", systemImage: "chart.bar.fill") }

            NavigationStack(path: $router.settingsPath) {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gear") }
        }
    }

    private var splitView: some View {
        NavigationSplitView {
            SidebarView(selection: $sidebarSelection)
        } detail: {
            NavigationStack(path: $router.clientsPath) {
                splitViewDetail
                .navigationDestination(for: AppDestination.self) { destination in
                    destinationView(for: destination)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 1000, minHeight: 700)
        #endif
    }

    @ViewBuilder
    private var splitViewDetail: some View {
        switch sidebarSelection {
        case .clients:
            ClientsView()
        case .insights:
            InsightsView()
        case .settings:
            SettingsView()
        case .none:
            Text("Select an item")
        }
    }

    // MARK: - Navigation Destination Factory

    @ViewBuilder
    private func destinationView(for destination: AppDestination) -> some View {
        switch destination {
        case .clientDetail(let client):
            ClientDetailView(client: client)

        case .petDetail(let pet):
            PetDetailView(pet: pet, namespace: Namespace().wrappedValue)

        case .visitDetail(let visit):
            VisitDetailView(visit: visit)

        case .petHistory(let pet):
            PetHistoryView(pet: pet)

        case .checkout(let pet):
            CheckoutView(pet: pet, visit: pet.activeVisit)
        }
    }
}
