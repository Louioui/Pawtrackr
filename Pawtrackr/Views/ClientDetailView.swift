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
    @State private var showContactEditor = false
    @State private var editingContact: EmergencyContact? = nil
    @State private var newContactName: String = ""
    @State private var newContactRelation: String = ""
    @State private var newContactPhone: String = ""
    @State private var contactPendingDelete: EmergencyContact? = nil
    @FocusState private var contactNameFocused: Bool

    // Inline client edit state
    @State private var isEditingClientInline = false
    @State private var editFirst: String = ""
    @State private var editLast: String = ""
    @State private var editPhone: String = ""
    @State private var editEmail: String = ""

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
        .sheet(isPresented: $showContactEditor) {
            NavigationStack {
                Form {
                    Section(editingContact == nil ? "New Emergency Contact" : "Edit Emergency Contact") {
                        TextField("Name", text: $newContactName)
                            .focused($contactNameFocused)
                        TextField("Relation", text: $newContactRelation)
                        TextField("Phone", text: $newContactPhone)
                            .onChange(of: newContactPhone) { _, v in
                                guard !v.isEmpty else { return }
                                // Clamp to core 10 digits; do not allow extensions in this field.
                                let formatted = PhoneUtils.formatAsYouType(v, includeExtension: false)
                                if formatted != v { newContactPhone = formatted }
                            }
                        #if os(iOS)
                            .keyboardType(.phonePad)
                            .textContentType(.telephoneNumber)
                        #endif
                    }
                }
                .navigationTitle(editingContact == nil ? "Add Contact" : "Edit Contact")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showContactEditor = false } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { addOrUpdateContact() } }
                }
                .task { contactNameFocused = true }
            }
        }
        .alert(item: $contactPendingDelete) { c in
            Alert(
                title: Text("Delete Contact?"),
                message: Text("This cannot be undone."),
                primaryButton: .destructive(Text("Delete")) { confirmDeleteContact(c) },
                secondaryButton: .cancel()
            )
        }
        .fullScreenCover(item: $checkoutPet) { pet in
            CheckoutView(pet: pet, visit: vm.activeVisit(for: pet))
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
                emergencyContactsCard(client: vm.client)
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
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    InitialsCircle(initials: clientInitials(client))
                        .frame(width: 48, height: 48)
                        .matchedGeometryEffect(id: client.id, in: namespace)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(client.fullName)
                            .font(.title3.weight(.semibold))
                        Text("Client since \(Formatters.monthYear.string(from: client.createdAt))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isEditingClientInline {
                        HStack(spacing: 8) {
                            Button { cancelInlineEdit(client) } label: { Image(systemName: "xmark.circle.fill") }
                            Button { saveInlineEdit(client) } label: { Image(systemName: "checkmark.circle.fill") }
                                .disabled(
                                    editFirst.trimmed.isEmpty ||
                                    editLast.trimmed.isEmpty ||
                                    (!editPhone.trimmed.isEmpty && PhoneUtils.toE164(editPhone) == nil)
                                )
                        }
                        .font(.title3)
                    } else {
                        Button { beginInlineEdit(client) } label: { Image(systemName: "ellipsis.circle") }
                            .font(.title3)
                            .accessibilityLabel("More actions")
                    }
                }

                if isEditingClientInline {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack { TextField("First Name", text: $editFirst).textFieldStyle(.roundedBorder); TextField("Last Name", text: $editLast).textFieldStyle(.roundedBorder) }
                        HStack {
                            TextField("Phone", text: $editPhone)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: editPhone) { _, v in
                                    guard !v.isEmpty else { return }
                                    let f = PhoneUtils.formatAsYouType(v, includeExtension: false)
                                    if f != v { editPhone = f }
                                }
                            #if os(iOS)
                                .keyboardType(.phonePad)
                                .textContentType(.telephoneNumber)
                            #endif
                            TextField("Email", text: $editEmail).textFieldStyle(.roundedBorder)
                        }
                    }
                } else {
                    VStack(spacing: 10) {
                        contactRow(icon: "phone.fill", text: PhoneUtils.display(client.phone ?? "") ?? "—") {
                            #if canImport(UIKit)
                            if let tel = PhoneUtils.telURLString(client.phone ?? ""), let url = URL(string: tel) { UIApplication.shared.open(url) }
                            #endif
                        } trailing: {
                            HStack(spacing: 8) {
                                #if canImport(UIKit)
                                if let sms = PhoneUtils.smsURLString(client.phone ?? ""), let smsURL = URL(string: sms) {
                                    Button { UIApplication.shared.open(smsURL) } label: { Image(systemName: "message.fill") }
                                }
                                if let tel = PhoneUtils.telURLString(client.phone ?? ""), let telURL = URL(string: tel) {
                                    Button { UIApplication.shared.open(telURL) } label: { Image(systemName: "phone.fill") }
                                }
                                #endif
                            }
                        }
                        contactRow(icon: "envelope.fill", text: (client.email ?? "—")) {
                            #if canImport(UIKit)
                            if let email = client.email, let url = URL(string: "mailto:\(email)") { UIApplication.shared.open(url) }
                            #endif
                        } trailing: {
                            #if canImport(UIKit)
                            if let email = client.email, let url = URL(string: "mailto:\(email)") {
                                Button { UIApplication.shared.open(url) } label: { Image(systemName: "envelope.fill") }
                            }
                            #endif
                        }
                        contactRow(icon: "mappin.and.ellipse", text: (client.address ?? "—")) {} trailing: {
                            #if canImport(UIKit)
                            if let addr = client.address?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed), let url = URL(string: "http://maps.apple.com/?q=\(addr)") {
                                Button { UIApplication.shared.open(url) } label: { Image(systemName: "map.fill") }
                            }
                            #endif
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
                    Text("Notes").font(.headline)
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
                    Text("Emergency Contacts").font(.headline)
                    Spacer()
                    Button {
                        editingContact = nil
                        newContactName = ""; newContactRelation = ""; newContactPhone = ""
                        showContactEditor = true
                    } label: { Image(systemName: "plus.circle.fill").font(.headline) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add emergency contact")
                }
                if client.emergencyContacts.isEmpty {
                    Text("No emergency contacts yet").font(.footnote).foregroundStyle(.secondary)
                } else {
                    ForEach(client.emergencyContacts) { c in
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
                            Button { beginEditContact(c) } label: { Label("Edit", systemImage: "pencil") }
                            Button(role: .destructive) { contactPendingDelete = c } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    private func confirmDeleteContact(_ contact: EmergencyContact) {
        modelContext.delete(contact)
        try? modelContext.save()
        viewModel?.refreshRecentVisits()
    }

    private func addOrUpdateContact() {
        let name = newContactName.trimmingCharacters(in: .whitespacesAndNewlines)
        let relation = newContactRelation.trimmingCharacters(in: .whitespacesAndNewlines)
        let phone = newContactPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let e164 = PhoneUtils.toE164(phone) else { return }
        if let editing = editingContact {
            editing.name = name
            editing.relation = relation.isEmpty ? nil : relation
            editing.phone = e164
        } else {
            let ec = EmergencyContact(name: name, relation: relation.isEmpty ? nil : relation, phone: e164)
            ec.owner = vm.client
            vm.client.emergencyContacts.append(ec)
        }
        try? modelContext.save()
        showContactEditor = false
        newContactName = ""; newContactRelation = ""; newContactPhone = ""
    }

    private func beginEditContact(_ c: EmergencyContact) {
        editingContact = c
        newContactName = c.name
        newContactRelation = c.relation ?? ""
        newContactPhone = PhoneUtils.display(c.phone) ?? c.phone
        showContactEditor = true
    }

    private var petsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pets (\(vm.pets.count))").font(.headline).padding(.horizontal)
            VStack(spacing: 12) {
                ForEach(vm.pets) { pet in
                    Card {
                        HStack(alignment: .top, spacing: 12) {
                            AvatarView(.pet(species: pet.species, gender: pet.gender, name: pet.name, imageData: pet.photoData), size: .md, ringWidth: 3)
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(pet.name).font(.headline)
                                        Text(pet.shortDescriptor).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    petStatusPill(pet)
                                }
                                HStack(spacing: 8) {
                                    actionButton(title: "Check In", systemImage: "arrow.down.right.circle.fill", tint: .blue) {
                                        vm.checkIn(pet: pet)
                                        withAnimation(Animations.fastEaseOut) { showSessionStartedToast = true }
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                            withAnimation(Animations.fastEaseOut) { showSessionStartedToast = false }
                                        }
                                    }
                                    .disabled(pet.activeVisit != nil)

                                    actionButton(title: "Check Out", systemImage: "creditcard.fill", tint: .green) {
                                        // Open checkout; pass active visit so it finalizes the ongoing session
                                        checkoutPet = pet
                                    }
                                    .disabled(pet.activeVisit == nil)

                                    actionButton(title: "History", systemImage: "clock.arrow.circlepath", borderOnly: true) {
                                        sheetDestination = .history(pet)
                                    }
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
                // Group by day to mirror the sample design
                let grouped = Dictionary(grouping: vm.recentVisits) { Calendar.current.startOfDay(for: $0.sortKeyDate) }
                let orderedDays = grouped.keys.sorted(by: >)
                VStack(spacing: 14) {
                    ForEach(orderedDays, id: \.self) { day in
                        let visits = grouped[day]!.sorted(by: { $0.sortKeyDate > $1.sortKeyDate })
                        HStack(spacing: 6) {
                            Text(Formatters.dateOnly.string(from: day)).font(.subheadline.weight(.semibold))
                            Text("\(visits.count) visits")
                                .font(.caption.weight(.bold))
                                .padding(.vertical, 2)
                                .padding(.horizontal, 6)
                                .background(Capsule().fill(Color.gray.opacity(0.15)))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        ForEach(visits) { visit in
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
        .overlay(alignment: .top) {
            VStack(spacing: 6) {
                if showSessionStartedToast {
                    SessionToast(text: "Session started", tint: .blue)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if showSavedToast {
                    SavedToast()
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.top, 8)
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

    // MARK: - Toolbar
    @State private var isDeleting = false
    
    @ToolbarContentBuilder
    private func toolbarContent(_ vm: ClientDetailViewModel) -> some ToolbarContent {
        // Rely on the system-provided back button to avoid duplicates
        ToolbarItem(placement: .topBarTrailing) {
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
            .tint(.red)
        }
    }

    // MARK: - Actions
    private func deleteClient() {
        isDeleting = true
        do {
            modelContext.delete(vm.client)
            try modelContext.save()

            isDeleting = false
            dismiss()
        } catch {
            isDeleting = false
            alertDestination = .deleteError(error.localizedDescription)
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
        client.setEmail(editEmail)
        try? modelContext.save()
        withAnimation(Animations.fastEaseOut) { isEditingClientInline = false }
        // Optional: show a small saved toast for inline edits
        withAnimation(Animations.fastEaseOut) { showSavedToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(Animations.fastEaseOut) { showSavedToast = false }
        }
    }

    @State private var showSavedToast = false
    @State private var showSessionStartedToast = false

    private struct SavedToast: View {
        var body: some View {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.white)
                Text("Saved successfully").foregroundStyle(.white)
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

@ViewBuilder private func petStatusPill(_ pet: Pet) -> some View {
    if let v = pet.activeVisit {
        HStack(spacing: 6) {
            Image(systemName: "clock")
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let secs = max(0, Int(Date().timeIntervalSince(v.startedAt)))
                Text(hms(secs)).monospacedDigit()
            }
        }
        .font(.caption.weight(.bold))
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.blue.opacity(0.12)))
        .foregroundStyle(.blue)
    } else {
        Text("Available")
            .font(.caption.weight(.bold))
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.12)))
            .foregroundStyle(.secondary)
    }
}

@ViewBuilder private func actionButton(title: String, systemImage: String, tint: Color = .blue, borderOnly: Bool = false, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        HStack { Image(systemName: systemImage); Text(title) }.font(.caption.weight(.semibold))
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
