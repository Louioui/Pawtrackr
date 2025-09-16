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
    weak var coordinator: ClientsCoordinator?
    @Namespace var namespace
    

    @State private var viewModel: ClientsViewModel?
    @State private var showingNewClientSheet = false
    @State private var clientPendingDeletion: Client? = nil
    @State private var showDeleteErrorAlert = false
    @State private var deleteErrorMessage: String = ""

    init(coordinator: ClientsCoordinator?) {
        self.coordinator = coordinator
        _viewModel = State(initialValue: nil)
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
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
        .navigationTitle("clients.title")
        .fabOverlay {
            FAB(systemImage: "plus", accessibilityLabel: NSLocalizedString("clients.add_client", comment: "")) {
                showingNewClientSheet = true
            }
        }
        .alert(
            clientPendingDeletion.map { String(format: NSLocalizedString("clients.delete_confirm_title_fmt", comment: ""), $0.fullName) } ?? "",
            isPresented: Binding(
                get: { clientPendingDeletion != nil },
                set: { if !$0 { clientPendingDeletion = nil } }
            )
        ) {
            Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) { clientPendingDeletion = nil }
            Button(NSLocalizedString("common.delete", comment: ""), role: .destructive) { deletePendingClient() }
        } message: {
            Text(NSLocalizedString("clients.delete_confirm_message", comment: ""))
        }
        .alert(NSLocalizedString("clients.delete_failed", comment: ""), isPresented: $showDeleteErrorAlert) {
            Button(NSLocalizedString("common.ok", comment: ""), role: .cancel) { }
        } message: {
            Text(deleteErrorMessage)
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

    @ViewBuilder
    private var searchBar: some View {
        if let viewModel {
            SearchField(text: Binding(get: { viewModel.searchText }, set: { viewModel.searchText = $0 }),
                        placeholder: NSLocalizedString("clients.search_placeholder", comment: ""))
                .padding(.horizontal)
        }
    }
    
    @ViewBuilder
    private func clientSections(_ viewModel: ClientsViewModel) -> some View {
        if !viewModel.inProgressClients.isEmpty {
            sectionHeader(NSLocalizedString("clients.in_progress", comment: ""), count: viewModel.inProgressCount, topPadding: 0)
            clientList(for: viewModel.inProgressClients)
        }
        sectionHeader(NSLocalizedString("clients.all_clients", comment: ""), count: viewModel.otherClients.count, topPadding: viewModel.inProgressClients.isEmpty ? 0 : 16)
        clientList(for: viewModel.otherClients)
    }
    
    @ViewBuilder
    private func clientList(for clients: [Client]) -> some View {
        LazyVStack(spacing: 10) {
            ForEach(clients) { client in
                Button(action: { coordinator?.showClientDetail(client: client, namespace: namespace) }) {
                    CardFactory.makeClientCard(client: client, onDelete: { clientPendingDeletion = client })
                        .matchedGeometryEffect(id: client.id, in: namespace)
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

    // MARK: - Delete
    private func deletePendingClient() {
        guard let client = clientPendingDeletion else { return }
        modelContext.delete(client)
        do {
            try modelContext.save()
            clientPendingDeletion = nil
            // Refresh list
            viewModel?.fetchClients()
        } catch {
            deleteErrorMessage = error.localizedDescription
            showDeleteErrorAlert = true
        }
    }
}
