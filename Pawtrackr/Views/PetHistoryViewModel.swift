
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
        NotificationCenter.default.addObserver(forName: .visitDidComplete, object: nil, queue: .main) { [weak self] note in
            guard let self else { return }
            guard let metadata = note.visitDidCompleteMetadata else {
                Task { await self.refresh() }
                return
            }

            if let endedAt = metadata.endedAt, !self.scope.contains(date: endedAt) {
                return
            }

            if metadata.petUUID == self.pet.uuid || metadata.petPersistentID == self.pet.persistentModelID {
                Task { await self.refresh() }
            }
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
            let amount = (v.isCompleted ? v.total : v.servicesSubtotal).moneyString
            return [date, services, duration, amount]
        }
        return Self.makeCSV(with: [header] + rows)
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
        let bounds = scope.dateBounds()
        var filter = VisitHistoryFilter(startDate: bounds.start, endDate: bounds.end, searchTokens: [])
        filter.petUUIDs = Set([pet.uuid])
        let descriptor = VisitHistoryFetchDescriptorBuilder.makeDescriptor(using: filter)
        do {
            visits = try modelContext.fetch(descriptor)
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

    static func makeCSV(with rows: [[String]]) -> Data {
        let esc: (String) -> String = { s in
            var v = s.replacingOccurrences(of: "\"", with: "\"\"")
            if v.contains(",") || v.contains("\n") || v.contains("\"") { v = "\"\(v)\"" }
            return v
        }
        let lines = rows.map { $0.map(esc).joined(separator: ",") }.joined(separator: "\n")
        return Data(lines.utf8)
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

// MARK: - Scope helpers
extension PetHistoryViewModel.Scope {
    func dateBounds(referenceDate: Date = .now, calendar: Calendar = .current) -> (start: Date?, end: Date?) {
        switch self {
        case .all:
            return (nil, nil)
        case .today:
            let start = calendar.startOfDay(for: referenceDate)
            let end = calendar.date(byAdding: .day, value: 1, to: start)
            return (start, end)
        case .thisWeek:
            guard let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: referenceDate)) else {
                return (nil, nil)
            }
            let end = calendar.date(byAdding: .day, value: 7, to: weekStart)
            return (weekStart, end)
        case .thisMonth:
            let comps = calendar.dateComponents([.year, .month], from: referenceDate)
            guard let start = calendar.date(from: comps) else {
                return (nil, nil)
            }
            let end = calendar.date(byAdding: .month, value: 1, to: start)
            return (start, end)
        }
    }

    func contains(date: Date, referenceDate: Date = .now, calendar: Calendar = .current) -> Bool {
        if self == .all { return true }
        let bounds = dateBounds(referenceDate: referenceDate, calendar: calendar)
        if let start = bounds.start, date < start { return false }
        if let end = bounds.end, date >= end { return false }
        return true
    }
}
