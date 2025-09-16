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
        ) { [weak self] notification in
            guard let self else { return }
            if let payload = notification.visitDidCompletePayload,
               self.shouldIgnore(payload: payload) {
                return
            }
            self.fetchVisits()
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

    private func dateBounds(for scope: Scope, reference: Date = Date()) -> (Date?, Date?) {
        let cal = Calendar.current
        switch scope {
        case .all:
            return (nil, nil)
        case .today:
            let start = cal.startOfDay(for: reference)
            let end = cal.date(byAdding: .day, value: 1, to: start)
            return (start, end)
        case .thisWeek:
            guard let start = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: reference)) else {
                return (nil, nil)
            }
            let end = cal.date(byAdding: .day, value: 7, to: start)
            return (start, end)
        }
    }

    private func shouldIgnore(payload: VisitDidCompleteNotification.Payload) -> Bool {
        guard scope != .all, let endedAt = payload.endedAt else { return false }
        let (start, end) = dateBounds(for: scope)
        if let start, endedAt < start { return true }
        if let end, endedAt >= end { return true }
        return false
    }

    private func makeDatePredicate(start: Date?, end: Date?) -> Predicate<Visit> {
        let lower = start
        let upper = end
        return #Predicate<Visit> { visit in
            guard let ended = visit.endedAt else { return false }
            if let lower, ended < lower { return false }
            if let upper, ended >= upper { return false }
            return true
        }
    }

    private func makeTokenPredicate(_ token: String, start: Date?, end: Date?) -> Predicate<Visit> {
        let lower = start
        let upper = end
        let q = token
        return #Predicate<Visit> { visit in
            guard let ended = visit.endedAt else { return false }
            if let lower, ended < lower { return false }
            if let upper, ended >= upper { return false }

            if visit.pet.name.localizedCaseInsensitiveContains(q) { return true }
            if let owner = visit.pet.owner {
                if owner.firstName.localizedCaseInsensitiveContains(q) { return true }
                if owner.lastName.localizedCaseInsensitiveContains(q) { return true }
            }
            if let note = visit.note, note.localizedCaseInsensitiveContains(q) { return true }
            if let reference = visit.payment?.externalReference,
               reference.localizedCaseInsensitiveContains(q) { return true }
            return false
        }
    }

    private func makeItemPredicate(_ token: String, start: Date?, end: Date?) -> Predicate<VisitItem> {
        let lower = start
        let upper = end
        let q = token
        return #Predicate<VisitItem> { item in
            guard let ended = item.visit.endedAt else { return false }
            if let lower, ended < lower { return false }
            if let upper, ended >= upper { return false }
            return item.name.localizedCaseInsensitiveContains(q)
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
        let now = Date()
        let (start, end) = dateBounds(for: scope, reference: now)
        do {
            let sortDescriptors = [SortDescriptor(\.endedAt, order: .reverse)]

            let searchTokens: [String] = {
                guard !trimmedQuery.isEmpty else { return [] }
                var seen: Set<String> = []
                var ordered: [String] = []
                let rawParts = trimmedQuery.split(whereSeparator: { $0.isWhitespace }).map { String($0) }
                for part in rawParts {
                    let normalized = part.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !normalized.isEmpty else { continue }
                    let key = normalized.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                    if seen.insert(key).inserted {
                        ordered.append(normalized)
                    }
                }
                return ordered
            }()

            let fetchedVisits: [Visit]
            if searchTokens.isEmpty {
                let descriptor = FetchDescriptor<Visit>(
                    predicate: makeDatePredicate(start: start, end: end),
                    sortBy: sortDescriptors
                )
                fetchedVisits = try modelContext.fetch(descriptor)
            } else {
                var visitMap: [UUID: Visit] = [:]
                for token in searchTokens {
                    let visitDescriptor = FetchDescriptor<Visit>(
                        predicate: makeTokenPredicate(token, start: start, end: end),
                        sortBy: sortDescriptors
                    )
                    let textMatches = try modelContext.fetch(visitDescriptor)
                    for visit in textMatches { visitMap[visit.uuid] = visit }

                    let itemDescriptor = FetchDescriptor<VisitItem>(predicate: makeItemPredicate(token, start: start, end: end))
                    let itemMatches = try modelContext.fetch(itemDescriptor)
                    for item in itemMatches {
                        let visit = item.visit
                        if visit.endedAt != nil {
                            visitMap[visit.uuid] = visit
                        }
                    }
                }
                fetchedVisits = visitMap.values.sorted { ($0.endedAt ?? $0.startedAt) > ($1.endedAt ?? $1.startedAt) }
            }

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
                    note: v.note,
                    paymentReference: v.payment?.externalReference,
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
    let note: String?
    let paymentReference: String?
    let total: Double
}

fileprivate enum RecentHistoryComputer {
    static func filterAndSummarize(snaps: [HistoryVisitSnap], query: String) -> (filteredIDs: Set<UUID>, totalRevenue: Double) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            let total = snaps.reduce(0.0) { $0 + $1.total }
            return (Set(snaps.map { $0.id }), total)
        }

        let normalizedTokens: [String] = {
            var seen: Set<String> = []
            var ordered: [String] = []
            let rawParts = trimmed.split(whereSeparator: { $0.isWhitespace }).map { String($0) }
            for part in rawParts {
                let normalized = part
                    .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalized.isEmpty else { continue }
                if seen.insert(normalized).inserted {
                    ordered.append(normalized)
                }
            }
            return ordered
        }()

        if normalizedTokens.isEmpty {
            let total = snaps.reduce(0.0) { $0 + $1.total }
            return (Set(snaps.map { $0.id }), total)
        }

        var ids: Set<UUID> = []
        var total: Double = 0
        for snap in snaps {
            let haystack = ([snap.petName, snap.ownerFirst, snap.ownerLast, snap.note ?? "", snap.paymentReference ?? ""] + snap.itemNames)
                .joined(separator: " ")
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            let matchesAllTokens = normalizedTokens.allSatisfy { haystack.contains($0) }
            if matchesAllTokens {
                ids.insert(snap.id)
                total += snap.total
            }
        }
        return (ids, total)
    }
}
