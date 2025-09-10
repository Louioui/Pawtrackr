//
//  ClientsView.swift
//  Pawtrackr
//
//  Client Center: now powered by a ViewModel for performant, debounced searching.
//  - Live timers are now handled efficiently by TimelineView inside ClientCard.
//  - Navigation to detail view is now implemented.
//

import SwiftUI
import SwiftData

struct ClientsView: View {
    @Environment(\.modelContext) private var modelContext
    
    // IMPROVEMENT: Initialize the ViewModel directly as a @State property.
    // This simplifies the view body and avoids using optionals.
    @State private var viewModel: ClientsViewModel
    @State private var showingNewClientSheet = false

    init() {
        // This is a common pattern to initialize a @State ViewModel that needs dependencies.
        // In a more complex app, you might use a dedicated dependency injection system.
        let tempContext = try! ModelContainer(for: Client.self).mainContext
        _viewModel = State(initialValue: ClientsViewModel(modelContext: tempContext))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    searchBar
                    
                    if viewModel.inProgressClients.isEmpty && viewModel.otherClients.isEmpty {
                        emptyState
                    } else {
                        clientSections
                    }
                }
                .padding(.vertical, 8)
                .padding(.bottom, 80) // Padding to avoid the FAB
            }
            .navigationTitle("Client Center")
            .fabOverlay {
                FAB(systemImage: "plus", accessibilityLabel: "Add New Client") {
                    showingNewClientSheet = true
                }
            }
            .sheet(isPresented: $showingNewClientSheet) {
                // When the sheet is dismissed, trigger a refresh to show the new client.
                viewModel.fetchClients()
            } content: {
                // FIX: Pass the model context to the sheet.
                NewClientSheet()
                    .environment(\.modelContext, modelContext)
            }
            .onAppear {
                // Also fetch on appear to catch changes made in other parts of the app.
                viewModel.fetchClients()
            }
        }
    }
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(
                "Search owners, pets, or phone",
                text: Binding(
                    get: { viewModel.searchText },
                    set: { viewModel.searchText = $0 }
                )
            )
            #if canImport(UIKit)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .submitLabel(.search)
            #endif
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(DS.ColorToken.surface, in: .capsule)
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private var clientSections: some View {
        if !viewModel.inProgressClients.isEmpty {
            sectionHeader("IN PROGRESS", count: viewModel.inProgressCount)
            clientList(for: viewModel.inProgressClients)
        }
        sectionHeader("ALL CLIENTS", count: viewModel.otherClients.count)
        clientList(for: viewModel.otherClients)
    }
    
    @ViewBuilder
    private func clientList(for clients: [Client]) -> some View {
        VStack(spacing: 10) {
            ForEach(clients) { client in
                NavigationLink(destination: ClientDetailView(client: client)) {
                    ClientCard(client: client)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
    }
    
    private var emptyState: some View {
        let isSearching = !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return ContentUnavailableView(
            isSearching ? "No Results Found" : "No Clients Yet",
            systemImage: isSearching ? "magnifyingglass" : "person.3.sequence.fill",
            description: Text(isSearching ? "No clients match \"\(viewModel.searchText)\"." : "Tap the + button to add your first client.")
        )
        .padding(40)
    }
    
    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            if count > 0 {
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 3)
                    .padding(.horizontal, 8)
                    .background(.thinMaterial, in: .capsule)
            }
        }
        .padding(.horizontal)
        .padding(.top, viewModel.inProgressClients.isEmpty ? 0 : 16)
    }
}
