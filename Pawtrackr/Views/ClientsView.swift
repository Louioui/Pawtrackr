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
#if canImport(UIKit)
import UIKit
#endif

struct ClientsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(NavigationRouter.self) private var router
    @Namespace var namespace

    @State private var viewModel: ClientsViewModel?
    @State private var showingNewClientSheet = false
    @State private var showNotifications = false
    @State private var storedNotifications: [NotificationItem] = []
    @State private var clientToDelete: Client?

    @FocusState private var isSearchFocused: Bool

    init() {
        _viewModel = State(initialValue: nil)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerBar

                if let viewModel {
                    if viewModel.inProgressClients.isEmpty && viewModel.otherClients.isEmpty {
                        emptyState(viewModel)
                    } else {
                        clientSections(viewModel)
                    }
                } else {
                    clientsSkeleton
                }
            }
            .padding(.top, 20)
            .padding(.bottom, 80) // Padding to avoid the FAB
        }
        .searchable(text: searchTextBinding,
                    isPresented: .init(get: { isSearchFocused }, set: { isSearchFocused = $0 }),
                    prompt: Text(NSLocalizedString("clients.search_placeholder", comment: "")))
        .focused($isSearchFocused)
        .background(DS.ColorToken.background)
        .ignoresSafeArea(edges: .top)
        .alert(item: errorBinding) { error in
            Alert(
                title: Text(NSLocalizedString("common.error", comment: "")),
                message: Text(error.localizedDescription),
                dismissButton: .default(Text(NSLocalizedString("common.ok", comment: "")))
            )
        }
        .alert(item: $clientToDelete) { client in
            Alert(
                title: Text("Delete Client"),
                message: Text("Are you sure you want to delete \(client.fullName)? This will also delete all their pets and visit history."),
                primaryButton: .destructive(Text("Delete")) {
                    viewModel?.deleteClient(client)
                },
                secondaryButton: .cancel()
            )
        }
        .fabOverlay {
            #if os(iOS)
            FAB(systemImage: "person.fill.badge.plus", accessibilityLabel: NSLocalizedString("clients.add_client", comment: "")) {
                showingNewClientSheet = true
            }
            .accessibilityIdentifier("clients.fab.addClient")
            #endif
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingNewClientSheet = true
                } label: {
                    Label(NSLocalizedString("clients.add_client", comment: ""), systemImage: "person.fill.badge.plus")
                }
                .keyboardShortcut("n", modifiers: .command)
                .accessibilityIdentifier("clients.toolbar.addClient")
            }

            ToolbarItem(placement: .primaryAction) {
                CloudKitStatusView()
            }

            ToolbarItem(placement: .navigation) {
                Button {
                    showNotifications = true
                } label: {
                    Image(systemName: "bell")
                }
                .accessibilityIdentifier("clients.toolbar.notifications")
            }

            ToolbarItem(placement: .navigation) {
                Button {
                    isSearchFocused = true
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .keyboardShortcut("f", modifiers: .command)
                .accessibilityIdentifier("clients.toolbar.search")
            }
        }
        .refreshable {
            // Hop to MainActor to call the isolated VM, then run cloud sync
            // concurrently with whatever local refresh the VM kicks off.
            await MainActor.run { viewModel?.fetchClients() }
            await CloudKitMonitor.shared.forceSync()
        }
        .navigationTitle("Clients")
        #if os(macOS)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    viewModel?.fetchClients()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
        #endif
        .sheet(isPresented: $showingNewClientSheet) {
        } content: {
            NewClientSheet(modelContext: modelContext)
        }
        .sheet(isPresented: $showNotifications) {
            NotificationsSheet(notifications: $storedNotifications)
        }
        .onAppear {
            if viewModel == nil { viewModel = ClientsViewModel(modelContext: modelContext) }
            viewModel?.fetchClients()
        }
        .onReceive(NotificationCenter.default.publisher(for: .clientDidCreate)) { note in
            if let id = note.createdClientID, note.clientCreatePhase == .created {
                storedNotifications.insert(NotificationItem(title: "Client Created", message: "A new client was added.", date: Date(), relatedID: id), at: 0)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .visitDidComplete)) { note in
            storedNotifications.insert(NotificationItem(title: "Visit Completed", message: "A visit was checked out.", date: Date(), relatedID: note.visitID), at: 0)
        }
    }

    @ViewBuilder
    private func clientSections(_ viewModel: ClientsViewModel) -> some View {
        if !viewModel.inProgressClients.isEmpty {
            sectionHeader(NSLocalizedString("clients.in_progress", comment: ""), count: viewModel.inProgressCount, topPadding: 0)
            clientList(for: viewModel.inProgressClients)
        }
        sectionHeader(NSLocalizedString("clients.all_clients", comment: ""), count: viewModel.otherClients.count, topPadding: viewModel.inProgressClients.isEmpty ? 0 : 16)
        VStack(spacing: 10) {
            clientList(for: viewModel.otherClients, enableInfiniteScroll: true)
            if viewModel.canLoadMore {
                Button(action: { viewModel.loadMore() }) {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(NSLocalizedString("common.load_more", comment: "Load More"))
                            .font(.footnote.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(DS.ColorToken.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
                .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private func clientList(for clients: [Client], enableInfiniteScroll: Bool = false) -> some View {
        LazyVStack(spacing: 10) {
            ForEach(Array(clients.enumerated()), id: \.element.id) { idx, client in
                Button(action: { router.navigateToClient(client) }) {
                    CardFactory.makeClientCard(client: client)
                        .matchedGeometryEffect(id: client.id, in: namespace)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("clients.row.\(client.firstName) \(client.lastName)")
                .contextMenu {
                    Button(role: .destructive) {
                        clientToDelete = client
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }

                    #if canImport(UIKit)
                    if let phone = client.phone, let tel = PhoneUtils.telURLString(phone), let url = URL(string: tel) {
                        Button {
                            UIApplication.shared.open(url)
                            HapticManager.selectionChanged()
                        } label: {
                            Label("Call", systemImage: "phone")
                        }
                    }
                    #endif

                    Button {
                        router.navigateToClient(client)
                    } label: {
                        Label("View Details", systemImage: "person.crop.circle")
                    }
                }
                .onAppear {
                    guard enableInfiniteScroll,
                          let vm = viewModel,
                          vm.canLoadMore,
                          !vm.isLoadingMore,
                          idx >= max(0, clients.count - 5) else { return }
                    vm.loadMore()
                }
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

    // MARK: - Header (Refined UI)
    private var headerBar: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Welcome Back!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Pawtrackr")
                    .font(.title.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 8)
            Button { showNotifications = true } label: {
                Image(systemName: "bell.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .overlay(alignment: .topTrailing) {
                        if notificationsCount > 0 {
                            Text("\(min(notificationsCount, 9))")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(minWidth: 16, minHeight: 16)
                                .padding(2)
                                .background(Color.red, in: Circle())
                                .offset(x: 6, y: -6)
                        }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Notifications, \(notificationsCount) unread")
        }
        .padding(.horizontal)
        .padding(.top, 16)
    }

    private var notificationsCount: Int { storedNotifications.count }

    private var searchTextBinding: Binding<String> {
        Binding(
            get: { viewModel?.searchText ?? "" },
            set: { viewModel?.searchText = $0 }
        )
    }

    private var errorBinding: Binding<AppError?> {
        Binding(
            get: { viewModel?.appError },
            set: { viewModel?.appError = $0 }
        )
    }

    private var clientsSkeleton: some View {
        VStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { _ in
                Card(elevation: .regular) {
                    HStack(spacing: 12) {
                        Circle().fill(Color.secondary.opacity(0.15)).frame(width: 40, height: 40)
                        VStack(alignment: .leading, spacing: 6) {
                            RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.15)).frame(width: 160, height: 12)
                            RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12)).frame(width: 120, height: 10)
                        }
                        Spacer()
                    }
                }
                .redacted(reason: .placeholder)
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Notifications UI
    private struct NotificationItem: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let date: Date
        let relatedID: PersistentIdentifier?
    }

    private struct NotificationsSheet: View {
        @Environment(\.dismiss) private var dismiss
        @Binding var notifications: [NotificationItem]
        var body: some View {
            NavigationStack {
                List {
                    if notifications.isEmpty {
                        ContentUnavailableView("No notifications", systemImage: "bell.slash")
                    } else {
                        ForEach(notifications) { n in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "bell.fill").foregroundStyle(.yellow)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(n.title).font(.subheadline.weight(.semibold))
                                    Text(n.message).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(n.date, style: .time).font(.caption2).foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 4)
                        }
                        .onDelete { idx in notifications.remove(atOffsets: idx) }
                    }
                }
                .navigationTitle("Notifications")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                    ToolbarItem(placement: .primaryAction) { if !notifications.isEmpty { Button("Clear All") { notifications.removeAll() } } }
                }
            }
        }
    }
}

private struct QuickStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        Card(elevation: .flat, showBorder: false) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundStyle(color)
                    Spacer()
                }
                Text(value)
                    .font(.title.weight(.bold))
                    .contentTransition(.numericText())
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
