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
    @State private var petPendingCheckIn: Pet? = nil

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

    // MARK: - Local State
    @State private var showDeleteConfirm = false
    @State private var showDeleteErrorAlert = false
    @State private var deleteErrorMessage: String = ""

    // MARK: - Init
    private let client: Client
    init(client: Client) { self.client = client }

    // MARK: - Body
    var body: some View {
        Group {
            if viewModel != nil {
                NavigationStack {
                    ScrollView {
                        VStack(spacing: 16) {
                            ownerHeader(client: vm.client)
                            notesCard(client: vm.client)
                            petsSection
                            recentHistorySection
                        }
                        .padding(.vertical, 8)
                    }
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
                    // Alerts bound while VM exists
                    .alert(
                        petPendingCheckIn.map { String(format: NSLocalizedString("client_details.checkin_confirm_title_fmt", comment: ""), $0.name) } ?? "",
                        isPresented: Binding(
                            get: { petPendingCheckIn != nil },
                            set: { if !$0 { petPendingCheckIn = nil } }
                        )
                    ) {
                        Button(NSLocalizedString("common.no", comment: ""), role: .cancel) { petPendingCheckIn = nil }
                        Button(NSLocalizedString("common.yes", comment: ""), role: .destructive) {
                            if let pet = petPendingCheckIn { vm.checkIn(pet: pet) }
                            petPendingCheckIn = nil
                        }
                    } message: {
                        Text(NSLocalizedString("client_details.checkin_confirm_message", comment: ""))
                    }
                    .alert(
                        String(format: NSLocalizedString("clients.delete_confirm_title_fmt", comment: ""), vm.client.fullName),
                        isPresented: $showDeleteConfirm
                    ) {
                        Button(NSLocalizedString("common.no", comment: ""), role: .cancel) { }
                        Button(NSLocalizedString("common.yes", comment: ""), role: .destructive) { deleteClient() }
                    } message: {
                        Text(NSLocalizedString("clients.delete_confirm_message", comment: ""))
                    }
                    .alert(NSLocalizedString("clients.delete_failed", comment: ""), isPresented: $showDeleteErrorAlert) {
                        Button(NSLocalizedString("common.ok", comment: ""), role: .cancel) { }
                    } message: {
                        Text(deleteErrorMessage)
                    }
                    .task { vm.refreshRecentVisits() }
                }
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

    // MARK: - Subviews
    private func ownerHeader(client: Client) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text(client.fullName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)

                VStack(alignment: .leading, spacing: 6) {
                    if let phone = client.phone, !phone.isEmpty {
                        Label(PhoneUtils.display(phone) ?? phone, systemImage: "phone.fill")
                    }
                    if let email = client.email, !email.isEmpty {
                        Label(email, systemImage: "envelope.fill")
                    }
                    if let address = client.address, !address.trimmed.isEmpty {
                        Label(address, systemImage: "house.fill")
                    }
                    if client.emergencyContactName?.trimmed.isEmpty == false || client.emergencyContactPhone?.trimmed.isEmpty == false {
                        let name = client.emergencyContactName?.trimmed ?? "Emergency Contact"
                        let phoneDisplay = client.emergencyContactPhone.flatMap { PhoneUtils.display($0) } ?? client.emergencyContactPhone
                        let composed: String = {
                            if let phoneDisplay, !phoneDisplay.isEmpty { return "\(name): \(phoneDisplay)" }
                            return name
                        }()
                        Label(composed, systemImage: "person.badge.key.fill")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
                        PetCard(
                            pet: pet,
                            activeVisit: vm.activeVisit(for: pet),
                            onViewDetails: { sheetDestination = .history(pet) },
                        onCheckIn: { petPendingCheckIn = pet },
                        onCheckOut: {
                            // Present checkout; keep timer live until confirmation
                            checkoutPet = pet
                        }
                    )
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
                        NavigationLink(destination: VisitDetailView(visit: visit)) {
                            VisitTimelineRow(visit: visit)
                        }
                        .buttonStyle(.plain)
                    }
                    if vm.recentVisits.count > 5 {
                        // Show the rest (up to current page)
                        ForEach(vm.recentVisits.dropFirst(5)) { visit in
                            NavigationLink(destination: VisitDetailView(visit: visit)) {
                                VisitTimelineRow(visit: visit)
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
                Button(role: .destructive) { showDeleteConfirm = true } label: { Label("client_details.delete", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
        // Confirm deletion
        ToolbarItem(placement: .bottomBar) {
            EmptyView()
                .confirmationDialog(
                    String(format: NSLocalizedString("clients.delete_confirm_title_fmt", comment: ""), vm.client.fullName),
                    isPresented: $showDeleteConfirm,
                    titleVisibility: .visible
                ) {
                    Button(NSLocalizedString("common.yes", comment: ""), role: .destructive) { deleteClient() }
                    Button(NSLocalizedString("common.no", comment: ""), role: .cancel) { }
                } message: {
                    Text(NSLocalizedString("clients.delete_confirm_message", comment: ""))
                }
        }
        ToolbarItem(placement: .automatic) {
            EmptyView()
                .alert(NSLocalizedString("clients.delete_failed", comment: ""), isPresented: $showDeleteErrorAlert) {
                    Button(NSLocalizedString("common.ok", comment: ""), role: .cancel) { }
                } message: {
                    Text(deleteErrorMessage)
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
            deleteErrorMessage = error.localizedDescription
            showDeleteErrorAlert = true
        }
    }
}
