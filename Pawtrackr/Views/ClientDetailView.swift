//
//  ClientDetailView.swift
//  Pawtrackr
//
//  Created by mac on 8/15/25.
//  Updated by Assistant on 2025-09-03.
//

import SwiftUI
import SwiftData
import OSLog

@MainActor
struct ClientDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // Lazy-initialized ViewModel to avoid context crashes
    @State private var viewModel: ClientDetailViewModel? = nil
    private var vm: ClientDetailViewModel { viewModel! }

    // Local sheet routing (do not depend on VM for UI routing)
    @State private var sheetDestination: SheetDestination?
    @State private var checkoutPet: Pet? = nil

    enum SheetDestination: Identifiable {
        case addPet
        case editClient
        case checkout(Pet)
        case history(Pet)

        var id: String {
            switch self {
            case .addPet:
                return "addPet"
            case .editClient:
                return "editClient"
            case .checkout(let pet):
                return "checkout_\(String(describing: pet.persistentModelID))"
            case .history(let pet):
                return "history_\(String(describing: pet.persistentModelID))"
            }
        }
    }
    
    enum AlertDestination: Identifiable {
        case checkIn(Pet)
        case deleteClient
        case deleteError(String)

        var id: String {
            switch self {
            case .checkIn(let pet):
                return "checkIn_\(pet.uuid.uuidString)"
            case .deleteClient:
                return "deleteClient"
            case .deleteError:
                return "deleteError"
            }
        }
    }

    @State private var alertDestination: AlertDestination?

    weak var coordinator: ClientsCoordinator?
    var namespace: Namespace.ID
    private var petsCoordinator: PetsCoordinator

    // MARK: - Init
    private let client: Client
    init(client: Client, coordinator: ClientsCoordinator?, namespace: Namespace.ID) {
        self.client = client
        self.coordinator = coordinator
        self.namespace = namespace
        self.petsCoordinator = PetsCoordinator(navigationController: coordinator!.navigationController)
    }

    // MARK: - Body
    var body: some View {
        Group {
            if viewModel != nil {
                navigationContent
            } else {
                ProgressView()
                    .padding()
            }
        }
        .onAppear {
            if viewModel == nil {
                let ctx = client.modelContext ?? modelContext
                viewModel = ClientDetailViewModel(client: client, modelContext: ctx)
                viewModel?.refreshRecentVisits()
            }
        }
    }

    private var navigationContent: some View {
        content
        .navigationTitle("client_details.title")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { toolbarContent(vm) }
        .fabOverlay {
            FAB(systemImage: "pawprint.fill", accessibilityLabel: "Add New Pet") {
                sheetDestination = .addPet
            }
        }
        .sheet(item: $sheetDestination) { destination in
            switch destination {
            case .addPet:
                AddPetSheet(client: vm.client)
            case .editClient:
                EditClientSheet(client: vm.client)
            case .checkout:
                EmptyView()
            case .history(let pet):
                PetHistoryView(pet: pet)
            }
        }
        .fullScreenCover(item: $checkoutPet) { pet in
            CheckoutView(pet: pet)
        }
        .alert(item: $alertDestination) { destination in
            switch destination {
            case .checkIn(let pet):
                Alert(
                    title: Text(String(format: NSLocalizedString("client_details.checkin_confirm_title_fmt", comment: ""), pet.name)),
                    message: Text(NSLocalizedString("client_details.checkin_confirm_message", comment: "")),
                    primaryButton: .default(Text(NSLocalizedString("common.yes", comment: ""))) {
                        vm.checkIn(pet: pet)
                    },
                    secondaryButton: .cancel(Text(NSLocalizedString("common.no", comment: "")))
                )
            case .deleteClient:
                Alert(
                    title: Text(String(format: NSLocalizedString("clients.delete_confirm_title_fmt", comment: ""), vm.client.fullName)),
                    message: Text(NSLocalizedString("clients.delete_confirm_message", comment: "")),
                    primaryButton: .destructive(Text(NSLocalizedString("common.yes", comment: ""))) {
                        deleteClient()
                    },
                    secondaryButton: .cancel(Text(NSLocalizedString("common.no", comment: "")))
                )
            case .deleteError(let message):
                Alert(
                    title: Text(NSLocalizedString("clients.delete_failed", comment: "")),
                    message: Text(message),
                    dismissButton: .default(Text(NSLocalizedString("common.ok", comment: "")))
                )
            }
        }
        .task { vm.refreshRecentVisits() }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 16) {
                ownerHeader(client: vm.client)
                notesCard(client: vm.client)
                petsSection
                recentHistorySection
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Subviews
    private func ownerHeader(client: Client) -> some View {
        Card {
            HStack(spacing: 12) {
                AvatarView(.pet(species: client.pets.first?.species ?? .dog, gender: client.pets.first?.gender ?? .male, name: client.pets.first?.name ?? "", imageData: client.pets.first?.photoData), size: .lg, ringWidth: 4)
                    .matchedGeometryEffect(id: client.id, in: namespace)
                VStack(alignment: .leading, spacing: 4) {
                    Text(client.fullName).font(.headline)
                    Text(client.primaryContact).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func notesCard(client: Client) -> some View {
        if let notes = client.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("client_details.notes_title", comment: "")).font(.headline)
                    Text(notes.trimmingCharacters(in: .whitespacesAndNewlines)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
        }
    }

    private var petsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("client_details.pets_title", comment: "")).font(.headline).padding(.horizontal)

            let columns: [GridItem] = [GridItem(.adaptive(minimum: 320, maximum: 400), spacing: 16)]
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(vm.pets) { pet in
                    Button(action: { petsCoordinator.showPetDetail(pet: pet, namespace: namespace) }) {
                        CardFactory.makePetCard(
                            pet: pet,
                            activeVisit: vm.activeVisit(for: pet),
                            onViewDetails: { sheetDestination = .history(pet) },
                            onCheckIn: { alertDestination = .checkIn(pet) },
                            onCheckOut: {
                                // Present checkout; keep timer live until confirmation
                                checkoutPet = pet
                            }
                        )
                        .matchedGeometryEffect(id: pet.id, in: namespace)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }

    private var recentHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(NSLocalizedString("client_details.recent_history", comment: "")).font(.headline)
                Spacer()
                Picker("Range", selection: Binding(
                    get: { vm.historyRange },
                    set: { vm.historyRange = $0 }
                )) {
                    Text("All").tag(ClientDetailViewModel.HistoryRange.all)
                    Text("Last 90d").tag(ClientDetailViewModel.HistoryRange.lastNDays(90))
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 260)
            }
            .padding(.horizontal)

            if vm.recentVisits.isEmpty {
                ContentUnavailableView("No History Yet", systemImage: "clock.badge.questionmark")
                    .padding(.vertical, 20)
            } else {
                VStack(spacing: 10) {
                    ForEach(vm.recentVisits.prefix(5)) { visit in
                        Button(action: { coordinator?.showVisitDetail(visit: visit) }) {
                            CardFactory.makeVisitTimelineRow(visit: visit)
                        }
                        .buttonStyle(.plain)
                    }
                    if vm.recentVisits.count > 5 {
                        // Show the rest (up to current page)
                        ForEach(vm.recentVisits.dropFirst(5)) { visit in
                            Button(action: { coordinator?.showVisitDetail(visit: visit) }) {
                                CardFactory.makeVisitTimelineRow(visit: visit)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if vm.canLoadMore {
                        Button {
                            vm.loadMore()
                        } label: {
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
                        .padding(.top, 6)
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.bottom, 80) // space for FAB
    }

    // MARK: - Toolbar
    @ToolbarContentBuilder
    private func toolbarContent(_ vm: ClientDetailViewModel) -> some ToolbarContent {
        // Rely on the system-provided back button to avoid duplicates
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button { sheetDestination = .editClient } label: { Label("client_details.edit", systemImage: "pencil") }
                Button(role: .destructive) { alertDestination = .deleteClient } label: { Label("client_details.delete", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    // MARK: - Actions
    private func deleteClient() {
        let client = vm.client
        modelContext.delete(client)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            alertDestination = .deleteError(error.localizedDescription)
        }
    }
}
