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

    // ViewModel is an ObservableObject (not @Observable), so use @StateObject
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
            .navigationDestination(for: Visit.self) { visit in
                VisitDetailView(visit: visit)
            }
        }
        .task { await vm.refresh() }
    }

    // MARK: - Subviews
    private func ownerHeader(client: Client) -> some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                // Reusable Avatar component
                AvatarView(.client(name: client.fullName), size: .lg)

                VStack(alignment: .leading, spacing: 6) {
                    Text(client.fullName).font(.title3.weight(.semibold))
                    if let phone = client.phone, !phone.isEmpty {
                        Label(PhoneUtils.display(phone) ?? phone, systemImage: "phone.fill")
                    }
                    if let email = client.email, !email.isEmpty {
                        Label(email, systemImage: "envelope.fill")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
                        NavigationLink(value: visit) {
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
        ToolbarItem(placement: .topBarLeading) {
            Button { dismiss() } label: { Image(systemName: "chevron.backward") }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { /* TODO: Edit owner info */ } label: { Text("Edit") }
        }
    }
}
