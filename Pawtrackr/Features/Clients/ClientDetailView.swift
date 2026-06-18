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

private struct ClientCheckoutRoute: Identifiable {
    let pet: Pet
    let visit: Visit

    var id: String {
        "checkout_\(pet.uuid.uuidString)_\(visit.uuid.uuidString)"
    }
}

@MainActor
struct ClientDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(GlobalEventBus.self) private var eventBus
    @Environment(WalkthroughController.self) private var walkthrough: WalkthroughController?

    // Lazy-initialized ViewModel to avoid context crashes
    @State private var viewModel: ClientDetailViewModel? = nil

    // Local sheet routing (do not depend on VM for UI routing)
    @State private var sheetDestination: SheetDestination?
    @State private var checkoutRoute: ClientCheckoutRoute? = nil

    enum SheetDestination: Identifiable {
        case addPet
        case editClient
        case history(Pet)
        case communication(Pet)

        var id: String {
            switch self {
            case .addPet:
                return "addPet"
            case .editClient:
                return "editClient"
            case .history(let pet):
                return "history_\(String(describing: pet.persistentModelID))"
            case .communication(let pet):
                return "communication_\(String(describing: pet.persistentModelID))"
            }
        }
    }
    
    enum AlertDestination: Identifiable {
        case checkIn(Pet)
        case deleteClient
        case deleteError(String)
        case deleteContact(EmergencyContact)

        var id: String {
            switch self {
            case .checkIn(let pet):
                return "checkIn_\(pet.uuid.uuidString)"
            case .deleteClient:
                return "deleteClient"
            case .deleteError:
                return "deleteError"
            case .deleteContact:
                // Singleton id — only one contact-delete alert can be in
                // flight at a time. Folding contact deletion into this enum
                // lets a single `.alert(item:)` host every confirmation,
                // which avoids SwiftUI's stacked-deprecated-Alert
                // presentation bug where the second `.alert(item:)`
                // silently never fires (the original cause of the trash
                // button looking broken).
                return "deleteContact"
            }
        }
    }

    @State private var alertDestination: AlertDestination?
    @State private var showContactEditor = false
    @State private var editingContact: EmergencyContact? = nil
    @State private var newContactName: String = ""
    @State private var newContactRelation: String = ""
    @State private var newContactPhone: String = ""
    @State private var validationError: String? = nil
    @FocusState private var contactNameFocused: Bool

    // Inline client edit state
    @State private var isEditingClientInline = false
    @State private var editFirst: String = ""
    @State private var editLast: String = ""
    @State private var editPhone: String = ""
    @State private var editEmail: String = ""

    @Environment(NavigationRouter.self) private var router
    @Query private var devices: [DeviceMetadata]
    private var namespace: Namespace.ID
    private static let walkthroughAnchors: Set<WalkthroughAnchorID> = [.cdOwner, .cdEmergency, .cdPets, .cdHistory]

    // MARK: - Init
    private let client: Client
    init(client: Client, namespace: Namespace.ID) {
        self.client = client
        self.namespace = namespace
    }

    // MARK: - Body
    var body: some View {
        Group {
            if let vm = viewModel {
                navigationContent(vm: vm)
            } else {
                ProgressView()
                    .padding()
            }
        }
        .onAppear {
            if viewModel == nil {
                let ctx = client.modelContext ?? modelContext
                viewModel = ClientDetailViewModel(client: client, modelContext: ctx, eventBus: eventBus)
                viewModel?.refreshRecentVisits()
            }
        }
    }

    private func navigationContent(vm: ClientDetailViewModel) -> some View {
        content(vm: vm)
            .navigationTitle("client_details.title")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .userActivity("com.pawtrackr.viewClient") { activity in
                activity.title = "Viewing \(client.fullName)"
                activity.userInfo = ["clientID": client.uuid.uuidString]
                activity.isEligibleForHandoff = true
            }
            .toolbar {
                toolbarContent(vm)
                macAddPetToolbarItem
            }
            #if os(iOS)
            .fabOverlay { addPetFab }
            #endif
            .sheet(item: $sheetDestination) { destination in
                destinationSheet(destination, vm: vm)
            }
            .sheet(isPresented: $showContactEditor) {
                contactEditorSheet
            }
            .modifier(CheckoutPresentationModifier(checkoutRoute: $checkoutRoute, vm: vm))
            // The deprecated `.alert(item:)` + `Alert(…)` API silently fails to
            // present when stacked under multiple `.sheet(item:)` modifiers
            // — that's why the Check In button looked broken to the user
            // (the alert never appeared, so vm.checkIn was never called).
            // Use the modern actions/message API instead.
            .alert(
                alertTitleText(for: alertDestination, vm: vm),
                isPresented: Binding(
                    get: { alertDestination != nil },
                    set: { if !$0 { alertDestination = nil } }
                ),
                presenting: alertDestination,
                actions: { destination in
                    alertActions(for: destination, vm: vm)
                },
                message: { destination in
                    alertMessage(for: destination)
                }
            )
            .onChange(of: (vm.client.pets ?? []).count) { _, _ in
                vm.refreshPets()
            }
            .task { vm.refreshRecentVisits() }
    }

    #if os(macOS)
    @ToolbarContentBuilder
    private var macAddPetToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { sheetDestination = .addPet } label: {
                Label(NSLocalizedString("a11y.add_new_pet", comment: ""), systemImage: "plus")
            }
        }
    }
    #else
    @ToolbarContentBuilder
    private var macAddPetToolbarItem: some ToolbarContent {
        EmptyToolbarContent()
    }
    #endif

    #if os(iOS)
    private var addPetFab: some View {
        FAB(systemImage: "pawprint.fill", accessibilityLabel: NSLocalizedString("a11y.add_new_pet", comment: "")) {
            sheetDestination = .addPet
        }
    }
    #endif

    @ViewBuilder
    private func destinationSheet(_ destination: SheetDestination, vm: ClientDetailViewModel) -> some View {
        switch destination {
        case .addPet:
            AddPetSheet(client: vm.client)
        case .editClient:
            EditClientSheet(client: vm.client)
        case .history(let pet):
            PetHistoryView(pet: pet)
        case .communication(let pet):
            CommunicationSheet(pet: pet, visit: nil)
        }
    }

    private var contactEditorSheet: some View {
        NavigationStack {
            Form {
                Section(editingContact == nil ? NSLocalizedString("client_detail.new_emergency_contact", comment: "") : NSLocalizedString("client_detail.edit_emergency_contact", comment: "")) {
                    TextField(NSLocalizedString("form.name", comment: ""), text: $newContactName)
                        .focused($contactNameFocused)
                    TextField(NSLocalizedString("form.relation", comment: ""), text: $newContactRelation)
                    TextField(NSLocalizedString("form.phone", comment: ""), text: $newContactPhone)
                        .phoneFieldFormatting($newContactPhone)
                }
            }
            .navigationTitle(editingContact == nil ? NSLocalizedString("client_detail.add_contact", comment: "") : NSLocalizedString("client_detail.edit_contact", comment: ""))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(NSLocalizedString("common.cancel", comment: "")) { showContactEditor = false } }
                ToolbarItem(placement: .confirmationAction) { Button(NSLocalizedString("common.save", comment: "")) { addOrUpdateContact() } }
            }
            .alert(AppLocalization.localized("common.validation_error", value: "Validation Error"), isPresented: Binding(get: { validationError != nil }, set: { if !$0 { validationError = nil } })) {
                Button(NSLocalizedString("common.ok", comment: "")) { validationError = nil }
            } message: {
                if let error = validationError {
                    Text(error)
                }
            }
            .task { contactNameFocused = true }
        }
    }

    private func alertTitleText(for destination: AlertDestination?, vm: ClientDetailViewModel) -> Text {
        switch destination {
        case .checkIn(let pet):
            return Text(String(format: NSLocalizedString("client_details.checkin_confirm_title_fmt", comment: ""), pet.name))
        case .deleteClient:
            return Text(String(format: NSLocalizedString("clients.delete_confirm_title_fmt", comment: ""), vm.client.fullName))
        case .deleteError:
            return Text(NSLocalizedString("clients.delete_failed", comment: ""))
        case .deleteContact:
            return Text(NSLocalizedString("client_detail.delete_contact_title", comment: ""))
        case .none:
            return Text("")
        }
    }

    @ViewBuilder
    private func alertActions(for destination: AlertDestination, vm: ClientDetailViewModel) -> some View {
        switch destination {
        case .checkIn(let pet):
            Button(NSLocalizedString("common.yes", comment: "")) {
                vm.checkIn(pet: pet)
                withAnimation(Animations.fastEaseOut) { showSessionStartedToast = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    withAnimation(Animations.fastEaseOut) { showSessionStartedToast = false }
                }
            }
            Button(NSLocalizedString("common.no", comment: ""), role: .cancel) {}
        case .deleteClient:
            Button(NSLocalizedString("common.yes", comment: ""), role: .destructive) {
                deleteClient(vm: vm)
            }
            Button(NSLocalizedString("common.no", comment: ""), role: .cancel) {}
        case .deleteError:
            Button(NSLocalizedString("common.ok", comment: ""), role: .cancel) {}
        case .deleteContact(let contact):
            Button(NSLocalizedString("common.delete", comment: ""), role: .destructive) {
                confirmDeleteContact(contact)
            }
            Button(NSLocalizedString("common.cancel", value: "Cancel", comment: ""), role: .cancel) {}
        }
    }

    @ViewBuilder
    private func alertMessage(for destination: AlertDestination) -> some View {
        switch destination {
        case .checkIn:
            Text(NSLocalizedString("client_details.checkin_confirm_message", comment: ""))
        case .deleteClient:
            Text(NSLocalizedString("clients.delete_confirm_message", comment: ""))
        case .deleteError(let message):
            Text(message)
        case .deleteContact:
            Text(NSLocalizedString("client_detail.delete_contact_message", comment: ""))
        }
    }

    private func content(vm: ClientDetailViewModel) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    ownerHeader(client: vm.client)
                        .walkthroughTarget(.cdOwner)
                    clientSafetyBanner(client: vm.client)
                    emergencyContactsCard(client: vm.client)
                        .walkthroughTarget(.cdEmergency)
                    notesCard(client: vm.client)
                    petsSection(vm: vm)
                        .walkthroughTarget(.cdPets)
                    recentHistorySection(vm: vm)
                        .walkthroughTarget(.cdHistory)
                    syncMetadataFooter(client: vm.client)
                }
                .padding(.vertical, 8)
            }
            .onAppear {
                scrollToWalkthroughAnchorIfNeeded(walkthrough?.currentStep?.anchor, proxy: proxy)
            }
            .onChange(of: walkthrough?.currentStep?.anchor) { _, anchor in
                scrollToWalkthroughAnchorIfNeeded(anchor, proxy: proxy)
            }
        }
        // Toasts must overlay the full scroll area so they appear at the top of
        // the screen regardless of scroll position. Previously this overlay was
        // attached to `recentHistorySection`, which rendered the toast far below
        // the fold — making the Check In button look like it did nothing.
        .overlay(alignment: .top) {
            VStack(spacing: 6) {
                if showSessionStartedToast {
                    SessionToast(
                        text: sessionStartedToastText.isEmpty
                            ? NSLocalizedString("client_detail.session_started", comment: "")
                            : sessionStartedToastText,
                        tint: .blue
                    )
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if showSavedToast {
                    SavedToast(text: NSLocalizedString("client_detail.saved_successfully", comment: ""))
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.top, 8)
            .allowsHitTesting(false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .clientDidCreate)) { notif in
            guard let id = notif.createdClientID, notif.clientCreatePhase == .navigated else { return }
            if id == vm.client.persistentModelID {
                withAnimation(Animations.fastEaseOut) { showSavedToast = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    withAnimation(Animations.fastEaseOut) { showSavedToast = false }
                }
            }
        }
    }

    private func scrollToWalkthroughAnchorIfNeeded(_ anchor: WalkthroughAnchorID?, proxy: ScrollViewProxy) {
        guard let anchor, Self.walkthroughAnchors.contains(anchor) else { return }

        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.35)) {
                proxy.scrollTo(anchor, anchor: .center)
            }
        }
    }

    private func syncMetadataFooter(client: Client) -> some View {
        HStack {
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                let name = devices.first { $0.deviceID == client.lastModifiedBy }?.name ?? "Unknown Device"
                Text(String(format: NSLocalizedString("client.metadata.last_modified_by_fmt", value: "Last modified by %@", comment: ""), name))
                Text(String(format: NSLocalizedString("client.metadata.at_fmt", value: "at %@", comment: ""), client.updatedAt.formatted(date: .abbreviated, time: .shortened)))
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    // MARK: - Subviews
    private func ownerHeader(client: Client) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(client.fullName)
                            .font(.title3.weight(.semibold))
                            .matchedGeometryEffect(id: "name-\(client.id)", in: namespace)
                        Text(String(format: NSLocalizedString("client_detail.client_since_fmt", comment: ""), Formatters.monthYear.string(from: client.createdAt)))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isEditingClientInline {
                        HStack(spacing: 8) {
                            Button { cancelInlineEdit(client) } label: { Image(systemName: "xmark.circle.fill") }
                                .accessibilityIdentifier("clientDetail.inlineEdit.cancel")
                            Button { saveInlineEdit(client) } label: { Image(systemName: "checkmark.circle.fill") }
                                .disabled(
                                    editFirst.trimmed.isEmpty ||
                                    editLast.trimmed.isEmpty ||
                                    (!editPhone.trimmed.isEmpty && PhoneUtils.toE164(editPhone) == nil)
                                )
                                .accessibilityIdentifier("clientDetail.inlineEdit.save")
                        }
                        .font(.title3)
                    } else {
                        HStack(spacing: 12) {
                            Button {
                                guard let firstPet = (client.pets ?? []).first else { return }
                                viewModel?.recordAttentionOutreach(method: "message")
                                // Route through the single `.sheet(item:)` so the
                                // template picker presents on macOS too — a separate
                                // `.sheet(isPresented:)` on the outer Group was being
                                // silently dropped by SwiftUI on macOS.
                                sheetDestination = .communication(firstPet)
                            } label: { Image(systemName: "message.circle.fill") }
                                .font(.title3)
                                .foregroundStyle(.blue)
                                .disabled((client.pets ?? []).isEmpty)
                                .accessibilityIdentifier("clientDetail.message")
                            Button { beginInlineEdit(client) } label: { Image(systemName: "ellipsis.circle") }
                                .font(.title3)
                                .accessibilityLabel(NSLocalizedString("a11y.more_actions", comment: ""))
                                .accessibilityIdentifier("clientDetail.editInline")
                        }
                    }
                }

                if isEditingClientInline {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            TextField(NSLocalizedString("new_client.first_name", comment: ""), text: $editFirst).textFieldStyle(.roundedBorder)
                            TextField(NSLocalizedString("new_client.last_name", comment: ""), text: $editLast).textFieldStyle(.roundedBorder)
                        }
                        HStack {
                            TextField(NSLocalizedString("new_client.phone", comment: ""), text: $editPhone)
                                .textFieldStyle(.roundedBorder)
                                .phoneFieldFormatting($editPhone)
                            TextField(NSLocalizedString("new_client.email", comment: ""), text: $editEmail).textFieldStyle(.roundedBorder)
                        }
                    }
                } else {
                    VStack(spacing: 10) {
                        contactRow(icon: "phone.fill", text: PhoneUtils.display(client.phone ?? "") ?? "—") {
                            if let tel = PhoneUtils.telURLString(client.phone ?? ""), let url = URL(string: tel) {
                                viewModel?.recordAttentionOutreach(method: "call")
                                URLOpener.open(url)
                            }
                        } trailing: {
                            HStack(spacing: 8) {
                                if PhoneUtils.smsURLString(client.phone ?? "") != nil {
                                    Button {
                                        guard let firstPet = (client.pets ?? []).first else { return }
                                        sheetDestination = .communication(firstPet)
                                    } label: { Image(systemName: "message.fill") }
                                    .accessibilityLabel(NSLocalizedString("client_detail.message", value: "Message", comment: ""))
                                }
                                if let tel = PhoneUtils.telURLString(client.phone ?? ""), let telURL = URL(string: tel) {
                                    Button {
                                        viewModel?.recordAttentionOutreach(method: "call")
                                        URLOpener.open(telURL)
                                    } label: { Image(systemName: "phone.fill") }
                                }
                            }
                        }
                        contactRow(icon: "envelope.fill", text: (client.email ?? "—")) {
                            if let email = client.email, let url = URL(string: "mailto:\(email)") { URLOpener.open(url) }
                        } trailing: {
                            if let email = client.email, let url = URL(string: "mailto:\(email)") {
                                Button { URLOpener.open(url) } label: { Image(systemName: "envelope.fill") }
                            }
                        }
                        contactRow(icon: "mappin.and.ellipse", text: (client.address ?? "—")) {} trailing: {
                            if let addr = client.address?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed), let url = URL(string: "http://maps.apple.com/?q=\(addr)") {
                                Button { URLOpener.open(url) } label: { Image(systemName: "map.fill") }
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func notesCard(client: Client) -> some View {
        if let notes = client.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "note.text").foregroundStyle(.yellow)
                VStack(alignment: .leading, spacing: 6) {
                    Text(NSLocalizedString("client_detail.notes", comment: "")).font(.headline)
                    Text(notes.trimmingCharacters(in: .whitespacesAndNewlines)).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.yellow.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
                    )
            )
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private func emergencyContactsCard(client: Client) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(NSLocalizedString("client_detail.emergency_contacts", comment: "")).font(.headline)
                    Spacer()
                    Button {
                        editingContact = nil
                        newContactName = ""; newContactRelation = ""; newContactPhone = ""
                        showContactEditor = true
                    } label: { Image(systemName: "plus.circle.fill").font(.headline) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(NSLocalizedString("client_detail.add_contact", comment: ""))
                }
                if (client.emergencyContacts ?? []).isEmpty {
                    Text(NSLocalizedString("client_detail.no_emergency_contacts", comment: "")).font(.footnote).foregroundStyle(.secondary)
                } else {
                    ForEach(client.emergencyContacts ?? [], id: \.uuid) { c in
                        HStack(spacing: 10) {
                            Image(systemName: "phone.fill").foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.name).font(.subheadline.weight(.semibold))
                                HStack(spacing: 6) {
                                    if let rel = c.relation, !rel.isEmpty { Text(rel).font(.caption).foregroundStyle(.secondary) }
                                    Text(PhoneUtils.display(c.phone) ?? c.phone).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            #if canImport(UIKit)
                            if let tel = PhoneUtils.telURLString(c.phone), let url = URL(string: tel) {
                                Link(destination: url) { Image(systemName: "phone.arrow.up.right").font(.body) }
                            }
                            #endif
                        }
                        .swipeActions(edge: .trailing) {
                            Button { beginEditContact(c) } label: { Label(AppLocalization.localized("common.edit", value: "Edit"), systemImage: "pencil") }
                            Button(role: .destructive) { alertDestination = .deleteContact(c) } label: { Label(NSLocalizedString("common.delete", comment: ""), systemImage: "trash") }
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    private func confirmDeleteContact(_ contact: EmergencyContact) {
        modelContext.delete(contact)
        do {
            try modelContext.save()
            CloudKitMonitor.shared.recordLocalChange("Deleted emergency contact")
        } catch {
            Logger.clientDetailView.error("Failed to delete contact: \(error.localizedDescription, privacy: .public)")
            CloudKitMonitor.shared.reportLocalSaveError(error, operation: "deleting emergency contact")
        }
        viewModel?.refreshRecentVisits()
    }

    private func addOrUpdateContact() {
        guard let vm = viewModel else { return }
        let name = newContactName.trimmingCharacters(in: .whitespacesAndNewlines)
        let relation = newContactRelation.trimmingCharacters(in: .whitespacesAndNewlines)
        let phone = newContactPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !name.isEmpty else {
            validationError = "Name is required."
            return
        }
        
        guard let e164 = PhoneUtils.toE164(phone) else {
            validationError = "A valid 10-digit US phone number is required."
            return
        }

        if let editing = editingContact {
            editing.name = name
            editing.relation = relation.isEmpty ? nil : relation
            editing.phone = e164
        } else {
            let ec = EmergencyContact(name: name, relation: relation.isEmpty ? nil : relation, phone: e164)
            ec.owner = vm.client
            modelContext.insert(ec)
            vm.client.emergencyContacts = (vm.client.emergencyContacts ?? []) + [ec]
        }
        do {
            try modelContext.save()
            CloudKitMonitor.shared.recordLocalChange("Saved emergency contact")
            showContactEditor = false
            newContactName = ""; newContactRelation = ""; newContactPhone = ""
        } catch {
            Logger.clientDetailView.error("Failed to save contact: \(error.localizedDescription, privacy: .public)")
            CloudKitMonitor.shared.reportLocalSaveError(error, operation: "saving emergency contact")
            validationError = "Failed to save to database."
        }
    }

    private func beginEditContact(_ c: EmergencyContact) {
        editingContact = c
        newContactName = c.name
        newContactRelation = c.relation ?? ""
        newContactPhone = PhoneUtils.display(c.phone) ?? c.phone
        showContactEditor = true
    }

    // MARK: - Safety (Aggressive behavior)

    /// Prominent, high-visibility warning shown at the top of the client center
    /// whenever any of the client's pets is flagged aggressive — so staff see
    /// the hazard before touching the dog.
    @ViewBuilder
    private func clientSafetyBanner(client: Client) -> some View {
        let aggressivePets = (client.pets ?? []).filter { $0.isAggressive }
        if !aggressivePets.isEmpty {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("client_detail.safety_alert.title", value: "Caution: Aggressive Behavior", comment: ""))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                    Text(String(
                        format: NSLocalizedString(
                            "client_detail.safety_alert.message_fmt",
                            value: "%@ is flagged as aggressive. Alert the team and handle with care.",
                            comment: ""
                        ),
                        aggressivePets.map(\.name).joined(separator: ", ")
                    ))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.95))
                    .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.ColorToken.danger, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("clientDetail.safetyBanner")
        }
    }

    /// Compact red flag rendered on an aggressive pet's row in the pet list.
    private var aggressivePetBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(NSLocalizedString("pet.safety.aggressive_badge", value: "Aggressive — handle with care", comment: ""))
                .font(.caption2.weight(.bold))
        }
        .foregroundStyle(.white)
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(DS.ColorToken.danger, in: Capsule())
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(NSLocalizedString("pet.safety.aggressive_a11y", value: "Warning: this pet is marked aggressive. Handle with care.", comment: ""))
    }

    private func petsSection(vm: ClientDetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(format: NSLocalizedString("client_detail.pets_count_fmt", comment: ""), vm.pets.count)).font(.headline).padding(.horizontal)
            VStack(spacing: 12) {
                ForEach(vm.pets) { pet in
                    let activeVisit = vm.activeVisit(for: pet)
                    let isCheckingIn = vm.isCheckingIn(pet)
                    Card {
                        HStack(alignment: .top, spacing: 12) {
                            AvatarView(.pet(species: pet.species, gender: pet.gender, name: pet.name, imageData: pet.photoData), size: .md, ringWidth: 3)
                            VStack(alignment: .leading, spacing: 6) {
                                if pet.isAggressive { aggressivePetBadge }
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(pet.name).font(.headline)
                                        Text(pet.shortDescriptor).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    petStatusPill(activeVisit)
                                }
                                HStack(spacing: 8) {
                                    actionButton(title: NSLocalizedString("client_detail.check_in", comment: ""), systemImage: "play.fill", tint: .blue) {
                                        if activeVisit != nil {
                                            sessionStartedToastText = String(
                                                format: AppLocalization.localized("client_detail.pet_already_in_session", value: "%@ is already in session"),
                                                pet.name
                                            )
                                            withAnimation(Animations.fastEaseOut) { showSessionStartedToast = true }
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                                withAnimation(Animations.fastEaseOut) { showSessionStartedToast = false }
                                            }
                                            HapticManager.notify(.warning)
                                            return
                                        }
                                        vm.checkIn(pet: pet)
                                        sessionStartedToastText = NSLocalizedString(
                                            "client_detail.session_started",
                                            value: "Session started for \(pet.name)",
                                            comment: ""
                                        )
                                        withAnimation(Animations.fastEaseOut) { showSessionStartedToast = true }
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                            withAnimation(Animations.fastEaseOut) { showSessionStartedToast = false }
                                        }
                                        HapticManager.notify(.success)
                                    }
                                    .opacity(activeVisit == nil && !isCheckingIn ? 1.0 : 0.55)
                                    .disabled(activeVisit != nil || isCheckingIn)
                                    .accessibilityIdentifier("clientDetail.pet.\(pet.name).checkIn")

                                    actionButton(title: NSLocalizedString("client_detail.check_out", comment: ""), systemImage: "stop.fill", tint: .blue) {
                                        if let visit = vm.activeVisit(for: pet) {
                                            checkoutRoute = ClientCheckoutRoute(pet: pet, visit: visit)
                                            HapticManager.notify(.success)
                                        } else {
                                            vm.refreshPets()
                                            HapticManager.notify(.warning)
                                        }
                                    }
                                    .opacity(activeVisit == nil ? 0.3 : 1.0)
                                    .disabled(activeVisit == nil)
                                    .accessibilityIdentifier("clientDetail.pet.\(pet.name).checkOut")

                                    actionButton(title: NSLocalizedString("client_detail.history", comment: ""), systemImage: "clock.arrow.circlepath", borderOnly: true) {
                                        sheetDestination = .history(pet)
                                    }
                                    .accessibilityIdentifier("clientDetail.pet.\(pet.name).history")
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }

    private func recentHistorySection(vm: ClientDetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(NSLocalizedString("client_details.recent_history", comment: "")).font(.headline)
                Spacer()
                Picker(NSLocalizedString("client_detail.all", comment: ""), selection: Binding(
                    get: { vm.historyRange },
                    set: { vm.historyRange = $0 }
                )) {
                    Text(NSLocalizedString("client_detail.all", comment: "")).tag(ClientDetailViewModel.HistoryRange.all)
                    Text(NSLocalizedString("client_detail.last_90d", comment: "")).tag(ClientDetailViewModel.HistoryRange.lastNDays(90))
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 260)
            }
            .padding(.horizontal)

            if vm.recentVisits.isEmpty {
                ContentUnavailableView(NSLocalizedString("client_detail.no_history_yet", comment: ""), systemImage: "clock.badge.questionmark")
                    .padding(.vertical, 20)
            } else {
                // Group by day to mirror the sample design
                let grouped = Dictionary(grouping: vm.recentVisits) { Calendar.current.startOfDay(for: $0.sortKeyDate) }
                let orderedDays = grouped.keys.sorted(by: >)
                VStack(spacing: 14) {
                    ForEach(orderedDays, id: \.self) { day in
                        let visits = (grouped[day] ?? []).sorted(by: { $0.sortKeyDate > $1.sortKeyDate })
                        HStack(spacing: 6) {
                            Text(Formatters.dateOnly.string(from: day)).font(.subheadline.weight(.semibold))
                            Text(String(format: NSLocalizedString("client_detail.visits_count_fmt", comment: ""), visits.count))
                                .font(.caption.weight(.bold))
                                .padding(.vertical, 2)
                                .padding(.horizontal, 6)
                                .background(Capsule().fill(Color.gray.opacity(0.15)))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        ForEach(visits) { visit in
                            Button(action: { router.navigateToVisit(visit) }) {
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
    @State private var isDeleting = false
    
    @ToolbarContentBuilder
    private func toolbarContent(_ vm: ClientDetailViewModel) -> some ToolbarContent {
        // Rely on the system-provided back button to avoid duplicates
        ToolbarItem(placement: .primaryAction) {
            Button(role: .destructive) {
                alertDestination = .deleteClient
            } label: {
                if isDeleting {
                    ProgressView()
                } else {
                    Image(systemName: "trash")
                }
            }
            .disabled(isDeleting)
            .accessibilityLabel(NSLocalizedString("client_details.delete", comment: ""))
            .accessibilityIdentifier("clientDetail.toolbar.delete")
            .tint(.red)
        }
    }

    // MARK: - Actions
    private func deleteClient(vm: ClientDetailViewModel) {
        Task { await performDeleteClient(vm: vm) }
    }

    @MainActor
    private func performDeleteClient(vm: ClientDetailViewModel) async {
        isDeleting = true

        let client = vm.client
        // Gather affected dates before deletion for summary updates
        let pets = client.pets ?? []
        let visits = pets.flatMap { $0.visits ?? [] }
        let paymentDates = visits.compactMap { $0.payment?.paidAt }
        let visitActivityDates = visits.map { $0.endedAt ?? $0.startedAt }

        // Delete the client; cascade rules will handle pets, visits, items, payments, and contacts.
        modelContext.delete(client)

        do {
            try modelContext.save()
            CloudKitMonitor.shared.recordLocalChange("Deleted client")

            // Rebuild summaries for affected days
            let cal = Calendar.current
            var affectedDays: Set<Date> = []
            for date in paymentDates { affectedDays.insert(cal.startOfDay(for: date)) }
            for date in visitActivityDates { affectedDays.insert(cal.startOfDay(for: date)) }
            
            for day in affectedDays {
                SummaryUpdater.rebuildDay(for: day, in: modelContext)
                await Task.yield() // Yield to keep UI responsive
            }

            isDeleting = false
            dismiss()
        } catch {
            isDeleting = false
            let message = String(describing: error)
            Logger.clientDetailView.error("Failed to delete client: \(message, privacy: .public)")
            CloudKitMonitor.shared.reportLocalSaveError(error, operation: "deleting client")
            alertDestination = .deleteError(message)
        }
    }

    private func beginInlineEdit(_ client: Client) {
        editFirst = client.firstName
        editLast = client.lastName
        editPhone = PhoneUtils.display(client.phone ?? "") ?? (client.phone ?? "")
        editEmail = client.email ?? ""
        withAnimation(Animations.fastEaseOut) { isEditingClientInline = true }
    }

    private func cancelInlineEdit(_ client: Client) {
        withAnimation(Animations.fastEaseOut) { isEditingClientInline = false }
    }

    private func saveInlineEdit(_ client: Client) {
        client.setFirstName(editFirst)
        client.setLastName(editLast)
        if editPhone.trimmed.isEmpty {
            client.setPhone(nil)
        } else if let e164 = PhoneUtils.toE164(editPhone) {
            client.setPhone(e164)
        } else {
            return
        }
        client.setEmail(editEmail.trimmed.isEmpty ? nil : editEmail)
        do {
            try modelContext.save()
            CloudKitMonitor.shared.recordLocalChange("Saved client changes")
        } catch {
            Logger.clientDetailView.error("Failed to save client edit: \(error.localizedDescription, privacy: .public)")
            CloudKitMonitor.shared.reportLocalSaveError(error, operation: "saving client changes")
            return
        }
        withAnimation(Animations.fastEaseOut) { isEditingClientInline = false }
        // Optional: show a small saved toast for inline edits
        withAnimation(Animations.fastEaseOut) { showSavedToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(Animations.fastEaseOut) { showSavedToast = false }
        }
    }

    @State private var showSavedToast = false
    @State private var showSessionStartedToast = false
    @State private var sessionStartedToastText: String = ""

    private struct SavedToast: View {
        var text: String
        var body: some View {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.white)
                Text(text).foregroundStyle(.white)
            }
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Capsule().fill(Color.green.opacity(0.9)))
            .shadow(radius: 6)
        }
    }

    private struct SessionToast: View {
        let text: String
        let tint: Color
        var body: some View {
            HStack(spacing: 8) {
                Image(systemName: "clock").foregroundStyle(.white)
                Text(text).foregroundStyle(.white)
            }
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Capsule().fill(tint.opacity(0.9)))
            .shadow(radius: 6)
        }
    }
}

private struct EmptyToolbarContent: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) { }
    }
}

private struct CheckoutPresentationModifier: ViewModifier {
    @Binding var checkoutRoute: ClientCheckoutRoute?
    let vm: ClientDetailViewModel

    func body(content: Content) -> some View {
        #if os(iOS)
        content.adaptiveCover(item: $checkoutRoute) { route in
            checkoutContent(for: route)
        }
        #else
        content.sheet(item: $checkoutRoute) { route in
            checkoutContent(for: route)
        }
        #endif
    }

    @ViewBuilder
    private func checkoutContent(for route: ClientCheckoutRoute) -> some View {
        CheckoutView(pet: route.pet, visit: route.visit)
            .onDisappear {
                vm.refreshPets()
                vm.refreshRecentVisits()
            }
    }
}

// MARK: - Local UI building blocks
private func clientInitials(_ client: Client) -> String {
    let f = client.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
    let l = client.lastName.trimmingCharacters(in: .whitespacesAndNewlines)
    let fi = f.first.map { String($0) } ?? ""
    let li = l.first.map { String($0) } ?? ""
    return (fi + li).uppercased()
}

private struct InitialsCircle: View {
    let initials: String
    var gradient: Gradient = Gradient(colors: [Color.blue, Color.blue.opacity(0.85)])
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(gradient: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(initials).font(.headline.weight(.semibold)).foregroundStyle(.white)
        }
    }
}

@ViewBuilder private func contactRow(icon: String, text: String, onTap: @escaping () -> Void, @ViewBuilder trailing: () -> some View) -> some View {
    HStack(spacing: 10) {
        Circle().fill(Color.gray.opacity(0.12)).frame(width: 28, height: 28).overlay(Image(systemName: icon).foregroundStyle(.secondary).font(.subheadline))
        Text(text).font(.subheadline.weight(.medium))
        Spacer()
        HStack(spacing: 8) { trailing() }
    }
    .contentShape(Rectangle())
    .onTapGesture(perform: onTap)
}

@ViewBuilder private func petStatusPill(_ activeVisit: Visit?) -> some View {
    if let v = activeVisit {
        HStack(spacing: 8) {
            Image(systemName: "clock")
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let secs = max(0, Int(Date().timeIntervalSince(v.startedAt)))
                Text(hms(secs)).monospacedDigit()
            }
        }
        .font(.callout.weight(.bold))
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.blue.opacity(0.12)))
        .foregroundStyle(.blue)
    } else {
        Text(NSLocalizedString("client_detail.available", comment: ""))
            .font(.caption.weight(.bold))
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.12)))
            .foregroundStyle(.secondary)
    }
}

@ViewBuilder private func actionButton(title: String, systemImage: String, tint: Color = .blue, borderOnly: Bool = false, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.callout)
            Text(title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
    .buttonStyle(.borderedProminent)
    .tint(borderOnly ? .clear : tint)
    .foregroundStyle(borderOnly ? Color.primary : Color.white)
    .overlay(
        RoundedRectangle(cornerRadius: 8).stroke(borderOnly ? Color.gray.opacity(0.3) : .clear, lineWidth: 1)
    )
}

private extension Logger {
    static let clientDetailView = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "ClientDetailView")
}

// Nonisolated small helper for duration string to use inside TimelineView
private func humanDuration(_ seconds: Int) -> String {
    let h = seconds / 3600
    let m = (seconds % 3600) / 60
    let s = seconds % 60
    if h > 0 { return m > 0 ? "\(h)h \(m)m" : "\(h)h" }
    if m > 0 { return s > 0 ? "\(m)m \(s)s" : "\(m)m" }
    return "\(s)s"
}

// Format as H:MM:SS with monospaced digits for stable layout
private func hms(_ seconds: Int) -> String {
    let h = seconds / 3600
    let m = (seconds % 3600) / 60
    let s = seconds % 60
    return String(format: "%d:%02d:%02d", h, m, s)
}
