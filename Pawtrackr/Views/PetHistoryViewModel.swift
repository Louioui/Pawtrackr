
//
//  PetHistoryViewModel.swift
//  Pawtrackr
//
//  Created by mac on 9/3/25.
//

import Foundation
import SwiftUI
import SwiftData

@MainActor
final class PetHistoryViewModel: ObservableObject {
    // MARK: - Types
    enum Scope: String, CaseIterable, Identifiable {
        case all = "All"
        case today = "Today"
        case thisWeek = "This Week"
        case thisMonth = "This Month"
        var id: String { rawValue }
    }

    // MARK: - Inputs / Environment
    private let modelContext: ModelContext
    @Published var pet: Pet

    // MARK: - Filtering
    @Published var scope: Scope = .thisMonth { didSet { Task { await refresh() } } }
    @Published var searchText: String = "" { didSet { applyFilters() } }

    // MARK: - Output
    @Published private(set) var visits: [Visit] = []              // raw fetch (date range)
    @Published private(set) var filtered: [Visit] = []            // search-applied

    // MARK: - KPIs
    @Published private(set) var totalVisits: Int = 0
    @Published private(set) var totalSpent: Decimal = .zero
    @Published private(set) var averageDuration: TimeInterval = 0

    var totalSpentString: String { totalSpent.moneyString }
    var averageDurationString: String { Formatters.durationString(from: Date(), to: Date().addingTimeInterval(averageDuration)) }

    // MARK: - Init
    init(pet: Pet, modelContext: ModelContext) {
        self.pet = pet
        self.modelContext = modelContext
        NotificationCenter.default.addObserver(forName: .visitDidComplete, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            Task { await self.refresh() }
        }
        Task { await refresh() }
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    // MARK: - Public
    func refresh() async {
        await fetchVisits()
        applyFilters()
        computeKPIs()
    }

    func exportCSV() -> Data {
        let header = ["Date","Services","Duration","Amount"]
        let rows: [[String]] = filtered.map { v in
            let date = v.startedAt.formatted(date: .abbreviated, time: .omitted)
            let services = v.items.map { $0.name }.joined(separator: ", ")
            let duration = Formatters.durationString(from: v.startedAt, to: v.endedAt ?? .now)
            let amountValue = v.isCompleted ? v.total : v.servicesSubtotal
            let amount = String(format: "%.2f", (amountValue as NSDecimalNumber).doubleValue)
            return [date, services, duration, amount]
        }
        let lines = ([header] + rows).map { $0.map { $0.csvEscaped }.joined(separator: ",") }.joined(separator: "\n")
        return Data(lines.utf8)
    }

    func exportPlainText() -> String {
        var out = ""
        for v in filtered {
            let date = v.startedAt.formatted(date: .abbreviated, time: .shortened)
            let duration = Formatters.durationString(from: v.startedAt, to: v.endedAt ?? .now)
            let amount = (v.isCompleted ? v.total : v.servicesSubtotal).moneyString
            let services = v.items.map { $0.name }.joined(separator: ", ")
            out += "\n• \(date) — \(services) — \(duration) — \(amount)"
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Private
    private func fetchVisits() async {
        let (start, end) = dateBounds(for: scope)
        // Push date bounds into the store-level predicate for performance
        let predicate = #Predicate<Visit> { v in
            if let s = start {
                if let e = end {
                    return v.startedAt >= s && v.startedAt < e
                } else {
                    return v.startedAt >= s
                }
            } else {
                if let e = end {
                    return v.startedAt < e
                } else {
                    return true
                }
            }
        }
        let descriptor = FetchDescriptor<Visit>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        do {
            var fetched = try modelContext.fetch(descriptor)
            // Filter by pet identity and require fully completed checkouts (paid visits only)
            let petID = pet.persistentModelID
            fetched = fetched.filter { $0.pet?.persistentModelID == petID && $0.isCompleted && $0.isPaid }
            visits = fetched
        } catch {
            visits = []
        }
    }

    private func applyFilters() {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { filtered = visits; return }
        let lc = q.localizedLowercase
        filtered = visits.filter { v in
            // match on item names, payment reference, or note
            if v.items.contains(where: { $0.name.localizedCaseInsensitiveContains(lc) }) { return true }
            if let note = v.note, note.localizedCaseInsensitiveContains(lc) { return true }
            if let ref = v.payment?.externalReference, ref.localizedCaseInsensitiveContains(lc) { return true }
            return false
        }
    }

    private func computeKPIs() {
        totalVisits = filtered.count
        let ended = filtered.compactMap { v -> (TimeInterval, Decimal)? in
            guard let end = v.endedAt else { return nil }
            let dur = max(0, end.timeIntervalSince(v.startedAt))
            let amt: Decimal = v.isCompleted ? v.total : v.servicesSubtotal
            return (dur, amt)
        }
        totalSpent = ended.reduce(.zero) { $0 + $1.1 }
        let totalDur = ended.reduce(0) { $0 + $1.0 }
        averageDuration = totalVisits > 0 ? totalDur / Double(max(1, totalVisits)) : 0
    }

    private func dateBounds(for scope: Scope) -> (Date?, Date?) {
        let cal = Calendar.current
        let now = Date()
        switch scope {
        case .all:
            return (nil, nil)
        case .today:
            let start = cal.startOfDay(for: now)
            guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return (start, nil) }
            return (start, end)
        case .thisWeek:
            guard let start = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)),
                  let end = cal.date(byAdding: .day, value: 7, to: start) else {
                return (nil, nil)
            }
            return (start, end)
        case .thisMonth:
            let comps = cal.dateComponents([.year, .month], from: now)
            guard let start = cal.date(from: comps),
                  let end = cal.date(byAdding: .month, value: 1, to: start) else {
                return (nil, nil)
            }
            return (start, end)
        }
    }
}

// MARK: - Shareable docs (optional Transferables)
struct PetHistoryCSV: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { $0.data }
    }
    let data: Data
}

struct PetHistoryText: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .plainText) { Data($0.text.utf8) }
    }
    let text: String
}
