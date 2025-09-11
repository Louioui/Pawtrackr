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
    
    // Initialize with the app's environment ModelContext to avoid schema/store mismatches.
    @State private var viewModel: ClientsViewModel?
    @State private var showingNewClientSheet = false

    init() { _viewModel = State(initialValue: nil) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let viewModel {
                        searchBar
                        if viewModel.inProgressClients.isEmpty && viewModel.otherClients.isEmpty {
                            emptyState(viewModel)
                        } else {
                            clientSections(viewModel)
                        }
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
                viewModel?.fetchClients()
            } content: {
                // FIX: Pass the model context to the sheet.
                NewClientSheet()
                    .environment(\.modelContext, modelContext)
            }
            .onAppear {
                // Also fetch on appear to catch changes made in other parts of the app.
                if viewModel == nil { viewModel = ClientsViewModel(modelContext: modelContext) }
                viewModel?.fetchClients()
            }
        }
        .searchable(text: Binding(
            get: { viewModel?.searchText ?? "" },
            set: { viewModel?.searchText = $0 }
        ), placement: .navigationBarDrawer(displayMode: .always))
    }

    @ViewBuilder
    private var searchBar: some View {
        if let viewModel {
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
    }
    
    @ViewBuilder
    private func clientSections(_ viewModel: ClientsViewModel) -> some View {
        if !viewModel.inProgressClients.isEmpty {
            sectionHeader("IN PROGRESS", count: viewModel.inProgressCount, topPadding: 0)
            clientList(for: viewModel.inProgressClients)
        }
        sectionHeader("ALL CLIENTS", count: viewModel.otherClients.count, topPadding: viewModel.inProgressClients.isEmpty ? 0 : 16)
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
    
    private func emptyState(_ viewModel: ClientsViewModel) -> some View {
        let isSearching = !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return ContentUnavailableView(
            isSearching ? "No Results Found" : "No Clients Yet",
            systemImage: isSearching ? "magnifyingglass" : "person.3.sequence.fill",
            description: Text(isSearching ? "No clients match \"\(viewModel.searchText)\"." : "Tap the + button to add your first client.")
        )
        .padding(40)
    }
    
    private func sectionHeader(_ title: String, count: Int, topPadding: CGFloat = 0) -> some View {
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
        .padding(.top, topPadding)
    }
}
