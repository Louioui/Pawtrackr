//
//  RecentHistoryView.swift
//  Pawtrackr
//
//  Reverse‑chronological feed of all completed visits across all clients.
//  ✅ New:
//   - Search (owner/pet/service)
//   - Scope filter: All / Today / This Week
//   - Summary chips: total visits + revenue for the current scope
//   - Same row layout (pet, date, duration, service chips, price, payment method)
//   - Tap row → PetHistoryView (fallback to VisitDetailView)
//
//  Created by mac on 8/14/25.
//  Updated by mac on 8/16/25.
//

import SwiftUI
import SwiftData

struct RecentHistoryView: View {
    // Fetch all Visits; we’ll filter to completed (endedAt != nil) in-memory
    @Query private var allVisits: [Visit]

    @State private var query: String = ""
    @State private var scope: Scope = .all
    @State private var refreshID = UUID()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header

                    // Summary chips for current scope
                    summaryChips
                        .padding(.horizontal)

                    let groups = groupedByDay(filteredVisits)
                    if groups.isEmpty {
                        ContentUnavailableView("No recent history",
                                               systemImage: "clock.badge.questionmark",
                                               description: Text("Completed checkouts will appear here."))
                            .padding(.top, 40)
                    } else {
                        ForEach(groups.keys.sorted(by: >), id: \.self) { day in
                            SectionHeader(date: day)
                                .padding(.horizontal)

                            VStack(spacing: 10) {
                                ForEach(groups[day] ?? [], id: \.persistentModelID) { visit in
                                    NavigationLink {
                                        PetHistoryView(pet: visit.pet)
                                    } label: {
                                        VisitRow(visit: visit)
                                            .padding(.horizontal)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.bottom, 20)
                    }
                }
                .padding(.top, 8)
            }
            .id(refreshID)
            .navigationTitle("Recent History")
            .onReceive(NotificationCenter.default.publisher(for: .visitDidComplete)) { _ in
                refreshID = UUID()
            }
        }
    }

    // MARK: - Data helpers

    private var completedVisitsSorted: [Visit] {
        allVisits
            .filter { $0.endedAt != nil }
            .sorted { ($0.endedAt ?? .distantPast) > ($1.endedAt ?? .distantPast) }
    }

    private var filteredVisits: [Visit] {
        let scopeFiltered = completedVisitsSorted.filter { v in
            guard let end = v.endedAt else { return false }
            switch scope {
            case .all:
                return true
            case .today:
                return Calendar.current.isDateInToday(end)
            case .thisWeek:
                let cal = Calendar.current
                guard let week = cal.dateInterval(of: .weekOfYear, for: Date()) else { return true }
                return end >= week.start && end <= week.end
            }
        }

        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return scopeFiltered }

        func norm(_ s: String) -> String {
            s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        }
        let tokens = norm(q).split(whereSeparator: \.isWhitespace).map(String.init)

        return scopeFiltered.filter { v in
            let ownerName: String
            if let owner = v.pet.owner {
                ownerName = "\(owner.firstName) \(owner.lastName)"
            } else {
                ownerName = ""
            }
            let owner = norm(ownerName)
            let pet = norm(v.pet.name)
            let services = v.items.map { norm($0.name) }
            return tokens.allSatisfy { t in
                owner.contains(t) || pet.contains(t) || services.contains(where: { $0.contains(t) })
            }
        }
    }

    private func groupedByDay(_ visits: [Visit]) -> [Date: [Visit]] {
        let cal = Calendar.current
        let pairs = visits.map { (cal.startOfDay(for: $0.endedAt ?? .distantPast), $0) }
        return Dictionary(grouping: pairs, by: { $0.0 })
            .mapValues { $0.map(\.1) }
    }

    // MARK: - UI pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Recent History")
                    .font(.title3).fontWeight(.semibold)
                Text("Completed sessions across all pets")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            // Search + scope
            HStack(spacing: 10) {
                SearchField(text: $query)
                ScopePicker(scope: $scope)
            }
            .padding(.horizontal)
        }
    }

    private var summaryChips: some View {
        let total = filteredVisits.count
        let revenue = filteredVisits.reduce(Decimal(0)) { $0 + $1.total }
        return HStack(spacing: 8) {
            // Corrected: Use the .style parameter for Pill
            Pill(text: "\(total) visits", style: .filled(tint: .blue.opacity(0.12), text: .blue))
            Pill(text: revenue.asCurrency, style: .filled(tint: .green.opacity(0.12), text: .green))
        }
    }
}

// MARK: - Scope

private enum Scope: String, CaseIterable, Identifiable {
    case all = "All"
    case today = "Today"
    case thisWeek = "This Week"

    var id: String { rawValue }
}

private struct ScopePicker: View {
    @Binding var scope: Scope
    var body: some View {
        Picker("", selection: $scope) {
            ForEach(Scope.allCases) { s in
                Text(s.rawValue).tag(s)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 240)
    }
}

// MARK: - Search field

private struct SearchField: View {
    @Binding var text: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search owner, pet, or service", text: $text)
                // .textInputAutocapitalization(.never) // Removed: Not available on macOS
                .disableAutocorrection(true)
                .accessibilityHint("Type an owner name, pet name, or service")
        }
        .padding(.vertical, 10).padding(.horizontal, 12)
        .background(.gray.opacity(0.1), in: Capsule())
    }
}

private struct SectionHeader: View {
    let date: Date
    var body: some View {
        Text(date.formatted(.dateTime.year().month().day()))
            .font(.headline)
            .foregroundStyle(.secondary)
            .padding(.top, 8)
    }
}

private struct VisitRow: View {
    let visit: Visit

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                // Left timeline dot colored by pet gender to echo the mock
                Circle()
                    .fill((visit.pet.gender == .female) ? .pink : .blue)
                    .frame(width: 10, height: 10)
                    .padding(.top, 6)

                VStack(alignment: .leading, spacing: 6) {
                    // Title & amount
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(titleText)
                                .font(.subheadline.weight(.semibold))
                            if let ended = visit.endedAt {
                                Text(ended.formatted(date: .abbreviated, time: .shortened))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(visit.totalUSDString)
                            .font(.subheadline.weight(.semibold))
                    }

                    // Services chips
                    if !visit.items.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(visit.items, id: \.persistentModelID) { item in
                                Pill(text: item.name)
                            }
                        }
                    }

                    // Duration + payment
                    HStack {
                        if let d = durationString {
                            Label(d, systemImage: "clock")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let pm = visit.payment?.method {
                            Label(pm.displayName, systemImage: pm.systemImage)
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var titleText: String {
        let petName = visit.pet.name
        // If you track a summarized “service type” you can show it here; fallback to pet name
        return petName
    }

    private var durationString: String? {
        guard let end = visit.endedAt else { return nil }
        let seconds = Int(end.timeIntervalSince(visit.startedAt))
        let h = seconds / 3600, m = (seconds % 3600) / 60
        return h > 0 ? "\(h) hr \(m) min" : "\(m) min"
    }
}


// MARK: - Small helpers

// Removed: These extensions were duplicates and caused build errors.
// The correct versions are in Formatters.swift and Payment.swift.
