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
                // Header + Quick stats
                headerBar
                if let dvm = dashVM { quickStats(dvm) } else { quickStatsSkeleton }

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
            .padding(.vertical, 8)
            .padding(.bottom, 80) // Padding to avoid the FAB
        }
        .navigationTitle("clients.title")
        .overlay(alignment: .bottom) { undoToast }

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
                    // Broadcast the second phase so detail can show a toast if desired.
                    NotificationCenter.default.post(name: .clientDidCreate, object: nil, userInfo: [
                        ClientDidCreateKey.clientID.rawValue: id,
                        ClientDidCreateKey.phase.rawValue: ClientDidCreatePhase.navigated.rawValue
                    ])
                }
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
        .sheet(isPresented: $showNotifications) {
            NotificationsSheet(notifications: $storedNotifications)
        }
        .onAppear {
            // Also fetch on appear to catch changes made in other parts of the app.
            if viewModel == nil { viewModel = ClientsViewModel(modelContext: modelContext) }
            if dashVM == nil { dashVM = DashboardViewModel(modelContext: modelContext) }
            viewModel?.fetchClients()
            Task { await dashVM?.refresh() }
        }
        // Collect app events into notifications list
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
                    CardFactory.makeClientCard(client: client, onDelete: { clientPendingDeletion = client })
                        .matchedGeometryEffect(id: client.id, in: namespace)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    #if canImport(UIKit)
                    if let phone = client.phone, let tel = PhoneUtils.telURLString(phone), let url = URL(string: tel) {
                        Button {
                            UIApplication.shared.open(url)
                            HapticManager.selectionChanged()
                        } label: { Label("Call", systemImage: "phone") }
                        .tint(.green)
                    }
                    #endif
                    Button(role: .destructive) {
                        clientPendingDeletion = client
                    } label: { Label("Delete", systemImage: "trash") }
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

    // MARK: - Header + Quick Stats (Tailwind-like styling)
    private var headerBar: some View {
        HStack {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.accentColor)
                    .frame(width: 32, height: 32)
                    .overlay(Image(systemName: "pawprint.fill").foregroundStyle(.white))
                Text("Pawtrackr").font(.headline)
            }
            Spacer()
            HStack(spacing: 8) {
                Button { showNotifications = true } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "bell.fill").foregroundStyle(.secondary)
                        if notificationsCount > 0 {
                            Circle().fill(Color.red).frame(width: 16, height: 16)
                                .overlay(Text("\(min(notificationsCount, 99))").font(.caption2.weight(.bold)).foregroundStyle(.white))
                                .offset(x: 6, y: -6)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Notifications")
            }
        }
        .padding(.horizontal)
    }

    private var notificationsCount: Int { storedNotifications.count }

    private func quickStats(_ vm: DashboardViewModel) -> some View {
        ZStack {
            LinearGradient(colors: [Color.green, Color.green.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Visits Today").font(.caption).foregroundStyle(.white.opacity(0.9))
                    Text("\(vm.kpi.appointmentsToday)").font(.title2.weight(.bold)).foregroundStyle(.white)
                }
                Spacer()
                Image(systemName: "calendar.badge.checkmark").font(.title2).foregroundStyle(.white.opacity(0.9))
            }
            .padding(14)
        }
        .frame(height: 76)
        .padding(.horizontal)
    }

    private var quickStatsSkeleton: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
                .frame(height: 76)
                .redacted(reason: .placeholder)
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
                .frame(height: 76)
                .redacted(reason: .placeholder)
        }
        .padding(.horizontal)
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

    // MARK: - Undo Toast
    @State private var showUndoToast = false
    @State private var lastDeleted: DeletedClientSnapshot? = nil
    private var undoToast: some View {
        Group {
            if showUndoToast {
                HStack(spacing: 12) {
                    Image(systemName: "trash.fill").foregroundStyle(.white)
                    Text("Client deleted").foregroundStyle(.white)
                    Spacer()
                    Button("Undo") { undoDelete() }.buttonStyle(.plain).foregroundStyle(.white)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Capsule().fill(Color.black.opacity(0.85)))
                .padding(.bottom, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func undoDelete() {
        guard let snap = lastDeleted else { return }
        let c = Client(firstName: snap.firstName, lastName: snap.lastName, phone: snap.phone)
        c.email = snap.email
        c.address = snap.address
        // Recreate pets (basic fields)
        for p in snap.pets {
            let pet = Pet(name: p.name, species: p.species)
            pet.gender = p.gender
            pet.breed = p.breed
            pet.color = p.color
            pet.photoData = p.photoData
            pet.owner = c
        }
        // Recreate contacts
        for ec in snap.contacts {
            let e = EmergencyContact(name: ec.name, relation: ec.relation, phone: ec.phone)
            e.owner = c
        }
        modelContext.insert(c)
        try? modelContext.save()
        withAnimation(Animations.fastEaseOut) { showUndoToast = false }
        viewModel?.fetchClients()
    }

    private struct DeletedClientSnapshot {
        let firstName: String
        let lastName: String
        let phone: String?
        let email: String?
        let address: String?
        let pets: [PetSnap]
        let contacts: [ContactSnap]
    }

    private struct PetSnap {
        let name: String
        let species: Species
        let gender: PetGender
        let breed: String?
        let color: String?
        let photoData: Data?
    }

    private struct ContactSnap {
        let name: String
        let relation: String?
        let phone: String
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

    // MARK: - Delete
    @State private var isDeleting = false
    
    @MainActor
    private func deletePendingClient() {
        guard let client = clientPendingDeletion else { return }
        isDeleting = true
        
        // Snapshot for undo
        lastDeleted = DeletedClientSnapshot(
            firstName: client.firstName,
            lastName: client.lastName,
            phone: client.phone,
            email: client.email,
            address: client.address,
            pets: client.pets.map { PetSnap(name: $0.name, species: $0.species, gender: $0.gender, breed: $0.breed, color: $0.color, photoData: $0.photoData) },
            contacts: client.emergencyContacts.map { ContactSnap(name: $0.name, relation: $0.relation, phone: $0.phone) }
        )
        
        do {
            modelContext.delete(client)
            try modelContext.save()

            isDeleting = false
            clientPendingDeletion = nil
            viewModel?.fetchClients()

            withAnimation(Animations.fastEaseOut) { showUndoToast = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                withAnimation(Animations.fastEaseOut) { showUndoToast = false }
                lastDeleted = nil
            }
        } catch {
            isDeleting = false
            deleteErrorMessage = error.localizedDescription
            showDeleteErrorAlert = true
        }
    }
}
