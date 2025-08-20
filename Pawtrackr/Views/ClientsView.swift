//
//  ClientsView.swift
//  Pawtrackr
//
//  Created by mac on 8/14/25.
//

import SwiftUI
import SwiftData

struct ClientsView: View {
    @Environment(\.modelContext) private var ctx
    @State private var showNewClient = false
    @State private var query = ""

    // Corrected: Use a valid comparator for SortDescriptor
    @Query(sort: [
        SortDescriptor(\Client.lastName),
        SortDescriptor(\Client.firstName)
    ])
    private var clients: [Client]
    
    // Added: A public init to resolve the "inaccessible initializer" error from PawtrackrApp
    init() { }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    VStack(spacing: 12) {
                        SearchField(text: $query)
                            .padding(.horizontal)

                        let filtered = filteredClients
                        if filtered.isEmpty {
                            ContentUnavailableView("No clients found",
                                                   systemImage: "person.fill.questionmark",
                                                   description: Text("Try another name, pet, or phone."))
                                .padding(.top, 40)
                        } else {
                            ForEach(filtered, id: \.persistentModelID) { client in
                                NavigationLink {
                                    ClientDetailView(client: client)
                                } label: {
                                    ClientCard(client: client, query: query)
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal)
                            }
                            .padding(.bottom, 96) // room for FAB
                        }
                    }
                    .padding(.top, 8)
                }
#if os(iOS)
                .scrollDismissesKeyboard(.interactively)
#endif

                // Corrected: Use the proper initializer for FAB
                FAB(systemImage: "plus", accessibilityLabel: "Add new client") {
                    showNewClient = true
                }
                .padding(.trailing, 20)
                .padding(.bottom, 24)
            }
            .navigationTitle("Client Center")
        }
        .sheet(isPresented: $showNewClient) {
            NewClientSheet()
        }
    }

    // MARK: - Filtering (name, phone, pet names)
    private var filteredClients: [Client] {
        let raw = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return clients }

        // normalize for diacritics/case
        func norm(_ s: String) -> String {
            s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        }
        // digits-only phone compare
        func digits(_ s: String) -> String { s.filter(\.isNumber) }
        let tokens = norm(raw).split(whereSeparator: \.isWhitespace).map(String.init)
        let rawDigits = digits(raw)

        return clients.filter { c in
            let first = norm(c.firstName)
            let last  = norm(c.lastName)
            // Corrected: Safely unwrap optional phone number
            let phone = digits(c.phone ?? "")
            let petNames = c.pets.map { norm($0.name) }

            return tokens.allSatisfy { t in
                first.contains(t) ||
                last.contains(t)  ||
                petNames.contains(where: { $0.contains(t) }) ||
                (!rawDigits.isEmpty && phone.contains(digits(t)))
            }
        }
    }
}

/// Compact search field to match your mock
private struct SearchField: View {
    @Binding var text: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search owners, pets, or US phone", text: $text)
                .accessibilityHint("Type an owner name, pet name, or phone number")
#if os(iOS)
                .textInputAutocapitalization(.never)
#endif
                .disableAutocorrection(true)
        }
        .padding(.vertical, 10).padding(.horizontal, 12)
        .background(.gray.opacity(0.1), in: Capsule())
    }
}

/// Card matches your design: name, phone, “In Progress” when any active visit,
/// pet icons (dog/cat) tinted by gender (blue=male, pink=female).
private struct ClientCard: View {
    let client: Client
    let query: String

    var body: some View {
        Card {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(highlightedName)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    HStack(spacing: 6) {
                        Image(systemName: "phone.fill")
                            .font(.caption2).foregroundStyle(.secondary)
                        // Corrected: Safely unwrap optional phone and format US phone
                        if let raw = client.phone, let formatted = PhoneUtils.display(raw) {
                            Text(formatted)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .fontWeight(phoneMatches ? .semibold : .regular)
                        } else {
                            Text("No phone")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                Spacer()
                if let since = activeSince {
                    HStack(spacing: 6) {
                        Pill(text: "In Progress", style: .filled(tint: .green.opacity(0.15), text: .green))
                        TimelineView(.everyMinute) { _ in
                            HStack(spacing: 4) {
                                Image(systemName: "clock")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(elapsedString(since))
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.gray.opacity(0.12), in: Capsule())
                        }
                    }
                }
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }

            // Pet icons row
            HStack(spacing: -8) {
                ForEach(client.pets.prefix(5), id: \.persistentModelID) { pet in
                    SpeciesAndGenderIcons.badge(for: pet.species,
                                                gender: pet.gender,
                                                size: 28)
                        .offset(x: 0)
                        .accessibilityLabel(Text("\(pet.name), \(pet.gender.displayName.lowercased())"))
                }
            }
            .padding(.top, 8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel({
            let phoneText: String = {
                if let raw = client.phone, let formatted = PhoneUtils.display(raw) { return formatted }
                return "not provided"
            }()
            return "Client: \(client.firstName) \(client.lastName), phone \(phoneText). \(isInProgress ? "In session" : "No active session"). \(client.pets.count) pets."
        }())
    }

    private var isInProgress: Bool {
        client.hasActiveVisit
    }

    private var activeSince: Date? {
        client.pets.compactMap { pet in
            pet.visits.first(where: { $0.endedAt == nil })?.startedAt
        }.min()
    }

    private func elapsedString(_ since: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(since))
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    private var normalizedTokens: [String] {
        let raw = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return [] }
        let base = raw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return base.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private var highlightedName: AttributedString {
        var a = AttributedString("\(client.firstName) \(client.lastName)")
        guard !normalizedTokens.isEmpty else { return a }
        for t in normalizedTokens {
            if let r = a.range(of: t, options: [.caseInsensitive, .diacriticInsensitive]) {
                a[r].font = .headline.bold()
            }
        }
        return a
    }

    private var phoneMatches: Bool {
        guard !normalizedTokens.isEmpty, let phone = client.phone else { return false }
        let phoneDigits = phone.filter(\.isNumber)
        if phoneDigits.isEmpty { return false }
        func digits(_ s: String) -> String { s.filter(\.isNumber) }
        return normalizedTokens.contains(where: { token in
            let d = digits(token)
            return !d.isEmpty && phoneDigits.contains(d)
        })
    }
}
