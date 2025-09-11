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

    // Use @StateObject for ObservableObject-based view models
    @StateObject private var vm: ClientDetailViewModel

    // Local sheet routing (do not depend on VM for UI routing)
    @State private var sheetDestination: SheetDestination?

    enum SheetDestination: Identifiable {
        case addPet
        case checkout(Pet)
        case history(Pet)

        var id: String {
            switch self {
            case .addPet:
                return "addPet"
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
    init(client: Client) {
        // Prefer the client's existing context; as a last resort, create a temporary container (debug-friendly)
        let ctx = client.modelContext ?? {
            do {
                let container = try ModelContainer(for: Client.self, Pet.self, Visit.self, VisitItem.self, Service.self, Payment.self)
                return container.mainContext
            } catch {
                fatalError("ModelContainer creation failed: \(error)")
            }
        }()
        // Initialize the @StateObject wrapper.
        _vm = StateObject(wrappedValue: ClientDetailViewModel(client: client, modelContext: ctx))
    }

    // MARK: - Body
    var body: some View {
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
            .navigationTitle(vm.client.fullName)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbarContent }
            .fabOverlay {
                FAB(systemImage: "pawprint.fill", accessibilityLabel: "Add New Pet") {
                    sheetDestination = .addPet
                }
            }
            .sheet(item: $sheetDestination) { destination in
                switch destination {
                case .addPet:
                    AddPetSheet(client: vm.client)
                case .checkout(let pet):
                    CheckoutView(pet: pet)
                case .history(let pet):
                    PetHistoryView(pet: pet)
                }
            }
        }
        // Global confirmation + alert so they always present (not tied to toolbar items)
        .alert(
            "Are you sure you want to delete \(vm.client.fullName)?",
            isPresented: $showDeleteConfirm
        ) {
            Button("No", role: .cancel) { }
            Button("Yes", role: .destructive) { deleteClient() }
        } message: {
            Text("This will permanently delete the client, their pets, and all visit history. This action cannot be undone.")
        }
        .alert("Delete Failed", isPresented: $showDeleteErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(deleteErrorMessage)
        }
        .task { vm.refreshRecentVisits() }
    }

    // MARK: - Subviews
    private func ownerHeader(client: Client) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Text(client.fullName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)

                if let phone = client.phone, !phone.isEmpty {
                    Label(PhoneUtils.display(phone) ?? phone, systemImage: "phone.fill")
                }
                if let email = client.email, !email.isEmpty {
                    Label(email, systemImage: "envelope.fill")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func notesCard(client: Client) -> some View {
        if let notes = client.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Client Notes").font(.headline)
                    Text(notes.trimmingCharacters(in: .whitespacesAndNewlines)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
        }
    }

    private var petsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pets").font(.headline).padding(.horizontal)

            let columns: [GridItem] = [GridItem(.adaptive(minimum: 320, maximum: 400), spacing: 16)]
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(vm.pets) { pet in
                    PetCard(
                        pet: pet,
                        activeVisit: vm.activeVisit(for: pet),
                        onViewDetails: { sheetDestination = .history(pet) },
                        onCheckIn: {
                            _ = vm.checkIn(pet: pet)
                        },
                        onCheckOut: {
                            // End the visit in Checkout flow; the checkout screen will attach payment
                            sheetDestination = .checkout(pet)
                        }
                    )
                }
            }
            .padding(.horizontal)
        }
    }

    private var recentHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent History").font(.headline).padding(.horizontal)

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
                }
                .padding(.horizontal)
            }
        }
        .padding(.bottom, 80) // space for FAB
    }

    // MARK: - Toolbar
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Rely on the system-provided back button to avoid duplicates
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Delete Client", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
        // Confirm deletion
        ToolbarItem(placement: .bottomBar) {
            EmptyView()
                .confirmationDialog(
                    "Are you sure you want to delete \(vm.client.fullName)?",
                    isPresented: $showDeleteConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Yes", role: .destructive) { deleteClient() }
                    Button("No", role: .cancel) { }
                } message: {
                    Text("This will permanently delete the client, their pets, and all visit history. This action cannot be undone.")
                }
        }
        ToolbarItem(placement: .automatic) {
            EmptyView()
                .alert("Delete Failed", isPresented: $showDeleteErrorAlert) {
                    Button("OK", role: .cancel) { }
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
