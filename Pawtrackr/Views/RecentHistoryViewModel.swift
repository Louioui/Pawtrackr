//
//  RecentHistoryViewModel.swift
//  Pawtrackr
//
//  Created by Assistant on 2025-09-03.
//

import SwiftUI
import SwiftData

@Observable
@MainActor
final class RecentHistoryViewModel {
    
    // MARK: - State
    var query: String = "" { didSet { scheduleFetch() } }
    var scope: Scope = .all { didSet { scheduleFetch() } }
    
    // MARK: - Published Data
    private(set) var groupedVisits: [Date: [Visit]] = [:]
    private(set) var sortedDays: [Date] = []
    private(set) var summaryVisitCount: Int = 0
    private(set) var summaryRevenueString: String = "$0.00"
    private(set) var isLoading: Bool = false
    
    // MARK: - Private Properties
    private var modelContext: ModelContext
    private var notificationToken: NSObjectProtocol? = nil
    private var searchTask: Task<Void, Never>? = nil
    private var workSeq: Int = 0 // guards async filtering application

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        // Auto-refresh when a checkout completes
        notificationToken = NotificationCenter.default.addObserver(
            forName: .visitDidComplete,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.fetchVisits()
        }
        fetchVisits()
    }

    // Note: For simplicity and to avoid actor‑isolation issues in deinit,
    // we are not explicitly removing the observer token. The VM is short‑lived
    // and the token will be released with it. If needed, refactor to selector-based
    // observers on NSObject and call removeObserver(self) in deinit on main.

    /// Allows the view to provide a real ModelContext from the environment
    /// after initializing with a temporary one. Triggers a refresh when changed.
    func setModelContext(_ newContext: ModelContext) {
        // Only swap if different to avoid redundant fetches
        if newContext !== self.modelContext {
            self.modelContext = newContext
            fetchVisits()
        }
    }
    
    private func scheduleFetch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300)) // Debounce search
            guard !Task.isCancelled else { return }
            self.fetchVisits()
        }
    }
    
    func fetchVisits() {
        self.isLoading = true
        #if DEBUG
        let t0 = Date()
        #endif
        let currentSeq = { workSeq &+= 1; return workSeq }()

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        // Compute date bounds for the selected scope and push them into the store predicate
        let cal = Calendar.current
        let now = Date()
        let (start, end): (Date?, Date?) = {
            switch scope {
            case .all:
                return (nil, nil)
            case .today:
                let s = cal.startOfDay(for: now)
                let e = cal.date(byAdding: .day, value: 1, to: s)!
                return (s, e)
            case .thisWeek:
                let s = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
                let e = cal.date(byAdding: .day, value: 7, to: s)!
                return (s, e)
            }
        }()
        // SwiftData predicate with date bounds only (text search remains in-memory)
        let predicate = #Predicate<Visit> { visit in
            visit.endedAt != nil &&
            (start == nil || visit.endedAt! >= start!) &&
            (end == nil || visit.endedAt! < end!)
        }

        do {
            let descriptor = FetchDescriptor<Visit>(predicate: predicate, sortBy: [SortDescriptor(\.endedAt, order: .reverse)])
            let fetchedVisits = try modelContext.fetch(descriptor)

            // Snapshot minimal data for off-main filtering and summary
            let snaps: [HistoryVisitSnap] = fetchedVisits.map { v in
                HistoryVisitSnap(
                    id: v.uuid,
                    startedAt: v.startedAt,
                    endedAt: v.endedAt,
                    petName: v.pet.name,
                    ownerFirst: v.pet.owner?.firstName ?? "",
                    ownerLast: v.pet.owner?.lastName ?? "",
                    itemNames: v.items.map { $0.name },
                    total: (v.total as NSDecimalNumber).doubleValue
                )
            }

            Task.detached(priority: .utility) { [currentSeq] in
                let result = RecentHistoryComputer.filterAndSummarize(snaps: snaps, query: trimmedQuery)
                await MainActor.run {
                    guard currentSeq == self.workSeq else { return }

                    // Apply filtered IDs to concrete visits
                    let filtered = fetchedVisits.filter { result.filteredIDs.contains($0.uuid) }
                    let calendar = Calendar.current
                    self.summaryVisitCount = filtered.count
                    self.summaryRevenueString = Decimal(result.totalRevenue).moneyString
                    self.groupedVisits = Dictionary(grouping: filtered, by: { calendar.startOfDay(for: $0.endedAt ?? $0.startedAt) })
                    self.sortedDays = self.groupedVisits.keys.sorted(by: >)
                    self.isLoading = false
                    #if DEBUG
                    let dt = Date().timeIntervalSince(t0)
                    print("History filter+apply in \(String(format: "%.2f", dt))s for \(snaps.count) visits")
                    #endif
                }
            }
        } catch {
            print("Failed to fetch recent history: \(error)")
            self.isLoading = false
        }
    }
    
    func exportCSV() -> String {
        let allVisits = sortedDays.flatMap { groupedVisits[$0] ?? [] }
        var lines: [String] = [
            "VisitID,StartedAt,EndedAt,Pet,Owner,Services,Amount,Payment,Reference,Notes"
        ]
        for v in allVisits {
            let id = v.uuid.uuidString
            let started = Formatters.iso8601.string(from: v.startedAt)
            let ended = v.endedAt.map { Formatters.iso8601.string(from: $0) } ?? ""
            let pet = v.pet.name.csvEscaped
            let owner = v.pet.owner?.fullName.csvEscaped ?? ""
            let services = v.items.map { $0.displayName.csvEscaped }.joined(separator: "; ")
            let amount = v.total.moneyString
            let payment = v.payment?.method.displayName.csvEscaped ?? ""
            let reference = v.payment?.externalReference?.csvEscaped ?? ""
            let notes = v.note?.replacingOccurrences(of: "\n", with: " ").csvEscaped ?? ""
            lines.append([id, started, ended, pet, owner, services, amount, payment, reference, notes].joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }
}

extension RecentHistoryViewModel {
    enum Scope: String, CaseIterable, Identifiable {
        case all = "All", today = "Today", thisWeek = "This Week"
        var id: String { rawValue }
    }
}

// MARK: - Background Compute Helpers
fileprivate struct HistoryVisitSnap: Sendable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date?
    let petName: String
    let ownerFirst: String
    let ownerLast: String
    let itemNames: [String]
    let total: Double
}

fileprivate enum RecentHistoryComputer {
    static func filterAndSummarize(snaps: [HistoryVisitSnap], query: String) -> (filteredIDs: Set<UUID>, totalRevenue: Double) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            let total = snaps.reduce(0.0) { $0 + $1.total }
            return (Set(snaps.map { $0.id }), total)
        }
        let needle = trimmed.folding(options: .diacriticInsensitive, locale: .current).lowercased()
        var ids: Set<UUID> = []
        var total: Double = 0
        for s in snaps {
            let fields: [String] = [
                s.petName,
                s.ownerFirst,
                s.ownerLast
            ] + s.itemNames
            let match = fields.contains { $0.folding(options: .diacriticInsensitive, locale: .current).lowercased().contains(needle) }
            if match {
                ids.insert(s.id)
                total += s.total
            }
        }
        return (ids, total)
    }
}
