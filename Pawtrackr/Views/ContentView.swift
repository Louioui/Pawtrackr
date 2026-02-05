//
//  ContentView.swift
//  Pawtrackr
//
//  Cross-platform main content view using NavigationStack.
//  Replaces CoordinatorView for iOS/macOS compatibility.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var appSettings: AppSettings
    @EnvironmentObject var authViewModel: AuthenticationViewModel

    /// Shared navigation router for programmatic navigation
    @State private var router = NavigationRouter()

    var body: some View {
        TabView {
            // MARK: - Clients Tab
            NavigationStack(path: $router.clientsPath) {
                ClientsView()
                    .navigationDestination(for: AppDestination.self) { destination in
                        destinationView(for: destination)
                    }
            }
            .tabItem {
                Label("Clients", systemImage: "person.3.fill")
            }

            // MARK: - Insights Tab
            NavigationStack(path: $router.insightsPath) {
                InsightsView()
            }
            .tabItem {
                Label("Insights", systemImage: "chart.bar.fill")
            }

            // MARK: - Settings Tab
            NavigationStack(path: $router.settingsPath) {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
        }
        .environment(router)
        #if os(macOS)
        .frame(minWidth: 900, minHeight: 600)
        #endif
    }

    // MARK: - Navigation Destination Factory

    @ViewBuilder
    private func destinationView(for destination: AppDestination) -> some View {
        switch destination {
        case .clientDetail(let client):
            ClientDetailView(client: client)

        case .petDetail(let pet):
            PetDetailViewModel.PetDetailView(pet: pet, namespace: Namespace().wrappedValue)

        case .visitDetail(let visit):
            VisitDetailView(visit: visit)

        case .petHistory(let pet):
            PetHistoryView(pet: pet)

        case .checkout(let pet):
            CheckoutView(pet: pet, visit: pet.activeVisit)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppSettings())
        .environmentObject(AuthenticationViewModel(modelContext: try! ModelContainer(for: Schema(PawtrackrSchema.models), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]).mainContext))
}
