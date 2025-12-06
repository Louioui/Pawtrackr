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
    weak var coordinator: ClientsCoordinator?
    @Namespace var namespace
    
    @State private var viewModel: ClientsViewModel?
    @State private var dashVM: DashboardViewModel?
    @State private var showingNewClientSheet = false
    @State private var showNotifications = false
    @State private var storedNotifications: [NotificationItem] = []
    @State private var clientToDelete: Client?

    init(coordinator: ClientsCoordinator?) {
        self.coordinator = coordinator
        _viewModel = State(initialValue: nil)
    }

    private var showErrorAlert: Binding<Bool> {
        Binding {
            viewModel?.errorMessage != nil
        } set: { _ in
            if viewModel != nil {
                viewModel?.errorMessage = nil
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerBar
                
                if let dvm = dashVM {
                    quickStats(dvm)
                } else {
                    quickStatsSkeleton
                }

                if let viewModel {
                    searchBar
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
        .background(DS.ColorToken.background)
        .ignoresSafeArea(edges: .top)
        .alert("common.error", isPresented: showErrorAlert) {
            Button("common.ok") {}
        } message: {
            Text(viewModel?.errorMessage ?? NSLocalizedString("errors.unknown", comment: "Unknown error message"))
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
            FAB(systemImage: "plus", accessibilityLabel: NSLocalizedString("clients.add_client", comment: "")) {
                showingNewClientSheet = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .clientOpenRequested)) { notification in
            guard let id = notification.requestedClientID else { return }
            viewModel?.fetchClients()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                guard let vm = viewModel else { return }
                let all = vm.inProgressClients + vm.otherClients
                if let client = all.first(where: { $0.persistentModelID == id }) {
                    withAnimation(Animations.gentleSpring) {
                        coordinator?.showClientDetail(client: client, namespace: namespace)
                    }
                    NotificationCenter.default.post(name: .clientDidCreate, object: nil, userInfo: [
                        ClientDidCreateKey.clientID.rawValue: id,
                        ClientDidCreateKey.phase.rawValue: ClientDidCreatePhase.navigated.rawValue
                    ])
                }
            }
        }
        .sheet(isPresented: $showingNewClientSheet) {
            viewModel?.fetchClients()
        } content: {
            NewClientSheet(modelContext: modelContext)
        }
        .sheet(isPresented: $showNotifications) {
            NotificationsSheet(notifications: $storedNotifications)
        }
        .onAppear {
            if viewModel == nil { viewModel = ClientsViewModel(modelContext: modelContext) }
            if dashVM == nil { dashVM = DashboardViewModel(modelContext: modelContext) }
            viewModel?.fetchClients()
            Task { await dashVM?.refresh() }
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
                Button(action: { coordinator?.showClientDetail(client: client, namespace: namespace) }) {
                    CardFactory.makeClientCard(client: client)
                        .matchedGeometryEffect(id: client.id, in: namespace)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
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
                        } label: { Label("Call", systemImage: "phone") }
                        .tint(.green)
                    }
                    #endif
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

    // MARK: - Header + Quick Stats (Refined UI)
    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Welcome Back!").font(.subheadline).foregroundStyle(.secondary)
                Text("Pawtrackr").font(.largeTitle.weight(.bold))
            }
            Spacer()
            Button { showNotifications = true } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    if notificationsCount > 0 {
                        Text("\(min(notificationsCount, 9))")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(5)
                            .background(Color.red)
                            .clipShape(Circle())
                            .offset(x: 8, y: -8)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Notifications")
        }
        .padding(.horizontal)
        .padding(.top, 20)
    }

    private var notificationsCount: Int { storedNotifications.count }

    private func quickStats(_ vm: DashboardViewModel) -> some View {
        HStack(spacing: 12) {
            QuickStatCard(
                title: "Visits Today",
                value: vm.kpi.appointmentsTodayText,
                icon: "calendar.badge.checkmark",
                color: .blue
            )
            QuickStatCard(
                title: "Revenue Today",
                value: vm.kpi.revenueTodayString,
                icon: "dollarsign.circle.fill",
                color: .green
            )
        }
        .padding(.horizontal)
    }

    private var quickStatsSkeleton: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.secondary.opacity(0.1))
                .frame(height: 88)
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.secondary.opacity(0.1))
                .frame(height: 88)
        }
        .padding(.horizontal)
        .redacted(reason: .placeholder)
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
