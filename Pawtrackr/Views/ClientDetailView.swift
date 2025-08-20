//
//  ClientDetailView.swift
//  Pawtrackr
//
//  Owner Details screen:
//  - Shows owner contact info
//  - Lists pets with unified actions: View Details, Check-In, Check-Out
//  - In-session timer shown inside each active pet card
//  - Recent History timeline for this owner
//
//  Created by mac on 8/15/25.
//

import SwiftUI
import SwiftData

#if os(iOS)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif

// Platform-aware neutral background (used for chips/capsules, etc.)
fileprivate extension Color {
    static var pawSecondaryBackground: Color {
    #if os(iOS)
        Color(UIColor.secondarySystemBackground)
    #elseif os(macOS)
        Color(nsColor: .windowBackgroundColor)
    #else
        Color.secondary.opacity(0.12)
    #endif
    }
}

struct ClientDetailView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    @Bindable var client: Client

    // Local timer to refresh durations for any active visits
    @State private var tick = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // UI state
    @State private var showingAddPet = false
    @State private var checkoutPet: Pet?
    @State private var showCheckoutSheet = false
    @State private var showHistory = false
    @State private var historyPet: Pet?
    @State private var refreshID = UUID()

    var body: some View {
        NavigationStack {
            ZStack {
                ScrollView {
                    VStack(spacing: 16) {
                        ownerHeader

                        // Pets Section
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Pets").font(.headline)
                                Spacer()
                            }
                            // Responsive grid for pet cards
                            let columns: [GridItem] = [
                                GridItem(.adaptive(minimum: 320, maximum: 400), spacing: 16)
                            ]
                            LazyVGrid(columns: columns, spacing: 16) {
                                ForEach(client.pets.sorted(by: { $0.name < $1.name })) { pet in
                                    PetCard(
                                        pet: pet,
                                        isActive: activeVisit(for: pet) != nil,
                                        durationString: durationString(for: pet),
                                        viewDetails: { viewDetails(for: pet) },
                                        checkIn: { startVisit(for: pet) },
                                        checkOut: {
                                            checkoutPet = pet
                                            showCheckoutSheet = true
                                        }
                                    )
                                }
                            }
                        }
                        .padding(.horizontal)

                        // Recent History
                        recentHistorySection
                            .padding(.horizontal)
                            .padding(.bottom, 24)
                    }
                    .padding(.top, 8)
                }
                // Floating Action Button (FAB)
                .overlay(
                    Button(action: {
                        showingAddPet = true
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 24, weight: .bold))
                            .padding()
                            .background(Circle().fill(Color.accentColor))
                    }
                    .shadow(radius: 5)
                    .padding(.bottom, 28)
                    .padding(.trailing, 28),
                    alignment: .bottomTrailing
                )
            }
            .id(refreshID)
            .navigationTitle("Owner Details")
            .toolbar {
                #if os(macOS)
                ToolbarItem(placement: .navigation) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .foregroundStyle(.blue)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        // TODO: Edit owner info
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                #else
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .foregroundStyle(.blue)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        // TODO: Edit owner info
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                #endif
            }
            .onReceive(timer) { now in
                tick = now // triggers re-render for timers
            }
            .sheet(isPresented: $showingAddPet) {
                AddPetSheet(client: client)
            }
            .sheet(isPresented: $showCheckoutSheet) {
                if let pet = checkoutPet {
                    InlineCheckoutSheet(
                        pet: pet,
                        visit: activeVisit(for: pet),
                        onConfirm: { amount, method, notes in
                            completeCheckout(for: pet, amount: amount, method: method, notes: notes)
                        }
                    )
                }
            }
            .sheet(isPresented: $showHistory) {
                if let p = historyPet {
                    PetHistoryView(pet: p)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .visitDidComplete)) { _ in
                refreshID = UUID()
            }
        }
    }
}

// MARK: - Owner Header

private extension ClientDetailView {
    var ownerHeader: some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                IconCircle(systemImage: "person.fill", size: 48, style: .tinted(Color.accentColor.opacity(0.15)))

                VStack(alignment: .leading, spacing: 6) {
                    Text("\(client.firstName) \(client.lastName)")
                        .font(.title3.weight(.semibold))

                    if let phone = client.phone, !phone.isEmpty {
                        Label(PhoneUtils.display(phone) ?? phone, systemImage: "phone.fill")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if let email = client.email, !email.isEmpty {
                        Label(email, systemImage: "envelope.fill")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if let address = client.address, !address.isEmpty {
                        Label(address, systemImage: "mappin.and.ellipse")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if client.hasActiveVisit {
                        Pill(text: "In Progress",
                             style: .filled(tint: DS.ColorToken.success.opacity(0.15),
                                            text: DS.ColorToken.success))
                            .padding(.top, 2)
                            .accessibilityLabel("In Progress")
                    }
                }
                Spacer()
            }
        }
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Pet Card

private struct PetCard: View {
    let pet: Pet
    let isActive: Bool
    let durationString: String?

    var viewDetails: () -> Void
    var checkIn: () -> Void
    var checkOut: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Gender accent bar
            Rectangle()
                .fill(pet.gender == .male ? Color.blue : pet.gender == .female ? Color.pink : Color.gray.opacity(0.3))
                .frame(height: 4)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.bottom, -4)
            Card {
                HStack(alignment: .top, spacing: 12) {
                    // Photo or icon (cross-platform)
                    #if os(iOS)
                    if let data = pet.photoData, let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipShape(Circle())
                    } else {
                        SpeciesAndGenderIcons.badge(for: pet.species, gender: pet.gender, size: 56)
                    }
                    #else
                    if let data = pet.photoData, let image = NSImage(data: data) {
                        Image(nsImage: image).resizable().scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipShape(Circle())
                    } else {
                        SpeciesAndGenderIcons.badge(for: pet.species, gender: pet.gender, size: 56)
                    }
                    #endif

                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(pet.name).font(.headline)
                            Spacer()
                            if isActive {
                                Pill(text: "In Session",
                                     style: .filled(tint: Color.accentColor.opacity(0.12),
                                                    text: Color.accentColor))
                            }
                        }
                        if let breed = pet.breed, !breed.isEmpty {
                            Text(breed).foregroundStyle(.secondary).font(.subheadline)
                        }

                        if isActive, let d = durationString {
                            HStack(spacing: 8) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .foregroundStyle(Color.accentColor)
                                    .font(.subheadline)
                                Text(d)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Color.accentColor)
                            }
                            .padding(8)
                            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 6)
                        }

                        // Unified actions inside the card
                        HStack(spacing: 8) {
                            Button(action: viewDetails) {
                                actionCapsule(title: "View Details", icon: "doc.text.magnifyingglass")
                            }
                            .accessibilityLabel("View Details")

                            Button(action: checkIn) {
                                actionCapsule(title: "Check In", icon: "play.circle.fill")
                            }
                            .disabled(isActive)
                            .opacity(isActive ? 0.4 : 1)
                            .accessibilityLabel("Check In")

                            Button(action: checkOut) {
                                actionCapsule(title: "Check Out", icon: "checkmark.circle.fill", gradient: true)
                            }
                            .disabled(!isActive)
                            .opacity(isActive ? 1 : 0.4)
                            .accessibilityLabel("Check Out")
                        }
                        .padding(.top, 8)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .accessibilityElement(children: .combine)
    }

    private func actionCapsule(title: String, icon: String, gradient: Bool = false) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(title).font(.subheadline.weight(.semibold))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background {
            if gradient {
                LinearGradient(colors: [Color.accentColor.opacity(0.8), Color.accentColor],
                               startPoint: .leading, endPoint: .trailing)
            } else {
                Color.pawSecondaryBackground
            }
        }
        .foregroundStyle(gradient ? .white : .primary)
        .clipShape(Capsule())
        .overlay(
            Capsule().strokeBorder(gradient ? .clear : .gray.opacity(0.2))
        )
        .shadow(color: gradient ? .black.opacity(0.1) : .clear, radius: 1, x: 0, y: 1)
        .contentShape(Capsule())
    }
}

// MARK: - Recent History

private extension ClientDetailView {
    var recentHistorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent History")
                .font(.headline)

            let visits = recentVisits
            if visits.isEmpty {
                ContentUnavailableView("No history yet",
                                       systemImage: "clock.badge.questionmark",
                                       description: Text("Completed checkouts will appear here."))
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 10) {
                    ForEach(visits, id: \.persistentModelID) { v in
                        VisitTimelineRow(visit: v)
                    }
                }
            }
        }
    }

    private var recentVisits: [Visit] {
        let all = client.pets.flatMap { $0.visits }.filter { $0.endedAt != nil }
        return all.sorted { ($0.endedAt ?? .distantPast) > ($1.endedAt ?? .distantPast) }
    }
}

private struct VisitTimelineRow: View {
    let visit: Visit

    var body: some View {
        Card {
            HStack(alignment: .top) {
                Circle()
                    .fill(DS.ColorToken.gender(visit.pet.gender))
                    .frame(width: 10, height: 10)
                    .padding(.top, 6)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(visit.pet.name)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(visit.totalUSDString)
                            .font(.subheadline.weight(.semibold))
                    }
                    if let ended = visit.endedAt {
                        Text(ended.formatted(date: .abbreviated, time: .shortened))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if !visit.items.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(visit.items, id: \.persistentModelID) { item in
                                Pill(text: item.name)
                            }
                        }
                        .padding(.top, 4)
                    }
                    HStack {
                        if let dur = visitDurationString(visit) {
                            Label(dur, systemImage: "clock").font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let pm = visit.payment?.method {
                            Label(pm.displayName, systemImage: pm.systemImage).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    private func visitDurationString(_ visit: Visit) -> String? {
        guard let end = visit.endedAt else { return nil }
        return Formatters.durationString(from: visit.startedAt, to: end)
    }
}

// MARK: - Actions & Helpers

private extension ClientDetailView {
    func viewDetails(for pet: Pet) {
        historyPet = pet
        showHistory = true
    }

    func startVisit(for pet: Pet) {
        guard activeVisit(for: pet) == nil else { return }
        let v = Visit(pet: pet)
        v.startedAt = Date()
        try? ctx.save()
    }

    func completeCheckout(for pet: Pet, amount: Decimal, method: Payment.Method, notes: String) {
        guard let v = activeVisit(for: pet) else { return }
        v.endedAt = Date()
        v.total = amount
        if !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            v.notes = notes
        }
        let payment = Payment(amount: amount, method: method)
        payment.paidAt = Date()
        if !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payment.note = notes
        }
        v.payment = payment
        try? ctx.save()
        // Notify others (e.g., ClientsView/Recent) to refresh if they observe this
        NotificationCenter.default.post(name: .visitDidComplete, object: nil)
    }

    func activeVisit(for pet: Pet) -> Visit? {
        pet.visits.first(where: { $0.endedAt == nil })
    }

    func durationString(for pet: Pet) -> String? {
        guard let v = activeVisit(for: pet) else { return nil }
        return Formatters.durationString(from: v.startedAt, to: Date())
    }
}

// MARK: - Inline Checkout Sheet

struct InlineCheckoutSheet: View {
    @Environment(\.dismiss) private var dismiss

    let pet: Pet
    let visit: Visit?
    var onConfirm: (_ amount: Decimal, _ method: Payment.Method, _ notes: String) -> Void

    @State private var amount: String = ""
    @State private var method: Payment.Method = .cash
    @State private var notes: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        #if os(iOS)
                        if let data = pet.photoData, let image = UIImage(data: data) {
                            Image(uiImage: image).resizable().scaledToFill()
                                .frame(width: 44, height: 44)
                                .clipShape(Circle())
                        } else {
                            SpeciesAndGenderIcons.badge(for: pet.species, gender: pet.gender, size: 44)
                        }
                        #else
                        if let data = pet.photoData, let image = NSImage(data: data) {
                            Image(nsImage: image).resizable().scaledToFill()
                                .frame(width: 44, height: 44)
                                .clipShape(Circle())
                        } else {
                            SpeciesAndGenderIcons.badge(for: pet.species, gender: pet.gender, size: 44)
                        }
                        #endif
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pet.name).font(.headline)
                            if let v = visit {
                                Text("In Session • \(durationString(from: v))")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("Service Charge") {
                    TextField("Amount", text: $amount)
                    #if os(iOS)
                        .keyboardType(.decimalPad)
                    #endif
                    Picker("Payment Method", selection: $method) {
                        ForEach(Payment.Method.allCases, id: \.self) { m in
                            Text(m.displayName).tag(m)
                        }
                    }
                }
                Section("Notes (optional)") {
                    TextEditor(text: $notes).frame(minHeight: 80)
                }
            }
            .navigationTitle("Check Out")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", role: .cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") {
                        // Robust USD parse (Decimal) using your helpers if present
                        let dec = amount.asDecimal(locale: Locale(identifier: "en_US_POSIX"))
                            ?? Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX")) ?? 0
                        onConfirm(dec, method, notes)
                        dismiss()
                    }
                    .disabled({
                        let dec = amount.asDecimal(locale: Locale(identifier: "en_US_POSIX"))
                            ?? Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX")) ?? 0
                        return dec <= 0
                    }())
                }
            }
            .onAppear {
                if amount.isEmpty, let v = visit, v.total > 0 {
                    amount = v.total.formatted(.currency(code: "USD"))
                }
            }
        }
    }

    private func durationString(from v: Visit) -> String {
        Formatters.durationString(from: v.startedAt, to: Date())
    }
}
