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
    var namespace: Namespace.ID

    init(namespace: Namespace.ID) {
        self.namespace = namespace
        _viewModel = State(initialValue: nil)
    }

    @State private var viewModel: ClientsViewModel?
    @State private var showingNewClientSheet = false
    @State private var showNotifications = false
    @State private var storedNotifications: [NotificationItem] = []
    @State private var clientToDelete: Client?
    @State private var isSearchPresented = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let viewModel {
                    filterChips(viewModel)
                    
                    if viewModel.inProgressClients.isEmpty && viewModel.otherClients.isEmpty && viewModel.needsAttentionClients.isEmpty {
                        emptyState(viewModel)
                    } else {
                        clientSections(viewModel)
                    }
                } else {
                    clientsSkeleton
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 80)
        }
        .searchable(text: searchTextBinding,
                    isPresented: $isSearchPresented,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: Text(NSLocalizedString("clients.search_placeholder", comment: "")))
        .background(DS.ColorToken.background)
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
            #if os(macOS)
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingNewClientSheet = true
                } label: {
                    Label(NSLocalizedString("clients.add_client", comment: ""), systemImage: "person.fill.badge.plus")
                }
                .keyboardShortcut("n", modifiers: .command)
                .accessibilityIdentifier("clients.toolbar.addClient")
            }
            #endif

            ToolbarItem(placement: .primaryAction) {
                CloudKitStatusView()
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                sortingMenu
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showNotifications = true
                } label: {
                    Image(systemName: "bell.fill")
                        .overlay(alignment: .topTrailing) {
                            if notificationsCount > 0 {
                                Text("\(min(notificationsCount, 9))")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 14, height: 14)
                                    .background(Color.red, in: Circle())
                                    .offset(x: 4, y: -4)
                            }
                        }
                }
                .accessibilityIdentifier("clients.toolbar.notifications")
                .accessibilityLabel("Notifications, \(notificationsCount) unread")
            }
        }
        .refreshable {
            // Hop to MainActor to call the isolated VM, then run cloud sync
            // concurrently with whatever local refresh the VM kicks off.
            await MainActor.run { viewModel?.fetchClients() }
            await CloudKitMonitor.shared.forceSync()
        }
        .navigationTitle("Clients")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
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
    private func filterChips(_ viewModel: ClientsViewModel) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ClientsViewModel.Filter.allCases, id: \.self) { filter in
                    Button {
                        withAnimation(.spring(duration: 0.3)) {
                            viewModel.selectedFilter = filter
                        }
                    } label: {
                        Text(filter.rawValue)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                viewModel.selectedFilter == filter ? DS.ColorToken.primary : Color.secondary.opacity(0.1),
                                in: Capsule()
                            )
                            .foregroundStyle(viewModel.selectedFilter == filter ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }

    private var sortingMenu: some View {
        Menu {
            Picker("Sort By", selection: sortOptionBinding) {
                ForEach(ClientsViewModel.SortOption.allCases, id: \.self) { option in
                    Label(option.rawValue, systemImage: sortIcon(for: option))
                        .tag(option)
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.title3)
        }
    }

    private func sortIcon(for option: ClientsViewModel.SortOption) -> String {
        switch option {
        case .name: return "textformat"
        case .lastVisit: return "clock"
        case .newest: return "calendar.badge.plus"
        }
    }

    private var sortOptionBinding: Binding<ClientsViewModel.SortOption> {
        Binding(
            get: { viewModel?.sortOption ?? .name },
            set: { viewModel?.sortOption = $0 }
        )
    }

    @ViewBuilder
    private func clientSections(_ viewModel: ClientsViewModel) -> some View {
        if !viewModel.inProgressClients.isEmpty {
            sectionHeader(NSLocalizedString("clients.in_progress", comment: ""), count: viewModel.inProgressCount, topPadding: 0)
            clientList(for: viewModel.inProgressClients)
        }
        
        if !viewModel.needsAttentionClients.isEmpty && viewModel.selectedFilter == .all {
            sectionHeader("Needs Attention", count: viewModel.needsAttentionClients.count, topPadding: 16)
            clientList(for: viewModel.needsAttentionClients)
        }

        sectionHeader(NSLocalizedString("clients.all_clients", comment: ""), count: viewModel.otherClients.count, topPadding: 16)
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
        LazyVStack(spacing: 12) {
            ForEach(Array(clients.enumerated()), id: \.element.id) { idx, client in
                Button(action: { router.navigateToClient(client) }) {
                    ClientCard(client: client, namespace: namespace)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("clients.row.\(client.firstName) \(client.lastName)")
                .contextMenu {
                    Button {
                        router.navigateToClient(client)
                    } label: {
                        Label("View Details", systemImage: "person.crop.circle")
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
                    
                    if let phone = client.phone, let sms = PhoneUtils.smsURLString(phone), let url = URL(string: sms) {
                        Button {
                            UIApplication.shared.open(url)
                            HapticManager.selectionChanged()
                        } label: {
                            Label("Message", systemImage: "message")
                        }
                    }

                    if let email = client.email, let url = URL(string: "mailto:\(email)") {
                        Button {
                            UIApplication.shared.open(url)
                            HapticManager.selectionChanged()
                        } label: {
                            Label("Email", systemImage: "envelope")
                        }
                    }
                    #endif

                    Divider()

                    Button(role: .destructive) {
                        clientToDelete = client
                    } label: {
                        Label("Delete", systemImage: "trash")
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
        var title = isSearching ? "No Results Found" : "No Clients Yet"
        var description = isSearching ? "No clients match \"\(viewModel.searchText)\"." : "Tap the + button to add your first client."
        var icon = isSearching ? "magnifyingglass" : "person.3.sequence.fill"

        if !isSearching {
            switch viewModel.selectedFilter {
            case .active:
                title = "No Active Sessions"
                description = "There are no pets currently checked in."
                icon = "hourglass.badge.plus"
            case .overdue:
                title = "All Caught Up!"
                description = "No clients have pets that are overdue for a visit."
                icon = "checkmark.seal.fill"
            case .missingInfo:
                title = "Data looks great!"
                description = "All your clients have phone numbers and emails on file."
                icon = "vial.viewfinder"
            default:
                break
            }
        }

        return ContentUnavailableView(
            title,
            systemImage: icon,
            description: Text(description)
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
