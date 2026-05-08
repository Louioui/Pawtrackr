//
//  RecentHistoryViewModel.swift
//  Pawtrackr
//
//  Created by Assistant on 2025-09-03.
//

import SwiftUI
import SwiftData
import Combine

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
    private var dataStore: DataStoreService
    private var searchTask: Task<Void, Never>?
    private var workSeq: UInt64 = 0
    private var observationTask: Task<Void, Never>?

    init(dataStore: DataStoreService) {
        self.dataStore = dataStore
        // Reactively observe changes to Visit entities
        self.observationTask = Task {
            for await _ in dataStore.observeChanges(Visit.self) {
                fetchVisits()
            }
        }
        Task { fetchVisits() }
    }

    // Internal tasks auto-cancel when the view model is released.
    
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
        let cal = Calendar.current
        let now = Date()
        let (start, end): (Date?, Date?) = {
            switch scope {
            case .all: return (nil, nil)
            case .today:
                let s = cal.startOfDay(for: now)
                guard let e = cal.date(byAdding: .day, value: 1, to: s) else { return (s, nil) }
                return (s, e)
            case .thisWeek:
                guard let s = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)),
                      let e = cal.date(byAdding: .day, value: 7, to: s) else { return (nil, nil) }
                return (s, e)
            }
        }()

        Task {
            do {
                let fetchedVisits = try await dataStore.fetchAsync(
                    #Predicate<Visit> { $0.endedAt != nil },
                    sortBy: [SortDescriptor(\.endedAt, order: .reverse)]
                ).filter { visit in
                    guard let endedAt = visit.endedAt else { return false }
                    if let s = start, endedAt < s { return false }
                    if let e = end, endedAt >= e { return false }
                    return true
                }

                // ... keep the rest of the filtering logic ...
                let snaps: [HistoryVisitSnap] = fetchedVisits.map { v in
                    HistoryVisitSnap(
                        id: v.uuid,
                        startedAt: v.startedAt,
                        endedAt: v.endedAt,
                        petName: v.pet?.name ?? "Unknown",
                        ownerFirst: v.pet?.owner?.firstName ?? "",
                        ownerLast: v.pet?.owner?.lastName ?? "",
                        itemNames: (v.items ?? []).map { $0.name },
                        total: (v.total as NSDecimalNumber).doubleValue
                    )
                }

                Task.detached(priority: .utility) { [currentSeq] in
                    let result = RecentHistoryComputer.filterAndSummarize(snaps: snaps, query: trimmedQuery)
                    await MainActor.run {
                        guard currentSeq == self.workSeq else { return }
                        let filtered = fetchedVisits.filter { result.filteredIDs.contains($0.uuid) }
                        let calendar = Calendar.current
                        self.summaryVisitCount = filtered.count
                        self.summaryRevenueString = Decimal(result.totalRevenue).moneyString
                        self.groupedVisits = Dictionary(grouping: filtered, by: { calendar.startOfDay(for: $0.endedAt ?? $0.startedAt) })
                        self.sortedDays = self.groupedVisits.keys.sorted(by: >)
                        self.isLoading = false
                    }
                }
            } catch {
                await MainActor.run {
                    print("Failed to fetch recent history: \(error)")
                    self.isLoading = false
                }
            }
        }
    }
    func exportCSV() -> String {
        let allVisits = sortedDays.flatMap { groupedVisits[$0] ?? [] }
        var lines: [String] = []
        lines.append("VisitID,StartedAt,EndedAt,Pet,Owner,Services,Amount,Payment,Reference,Notes")
        
        for v in allVisits {
            let id = v.uuid.uuidString
            let started = Formatters.iso8601.string(from: v.startedAt)
            let ended = v.endedAt.map { Formatters.iso8601.string(from: $0) } ?? ""
            let pet = (v.pet?.name ?? "Unknown").csvEscaped
            let owner = (v.pet?.owner?.fullName ?? "").csvEscaped
            let serviceNames = (v.items ?? []).map { $0.displayName.csvEscaped }
            let services = "\"\(serviceNames.joined(separator: "; "))\""
            let amount = v.total.moneyString
            let payment = (v.payment?.method.displayName ?? "").csvEscaped
            let reference = (v.payment?.externalReference ?? "").csvEscaped
            let notes = (v.note ?? "").replacingOccurrences(of: "\n", with: " ").csvEscaped
            
            let row: [String] = [id, started, ended, pet, owner, services, amount, payment, reference, notes]
            lines.append(row.joined(separator: ","))
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
        
        var ids: Set<UUID> = []
        var total: Double = 0
        for s in snaps {
            let fields: [String] = [s.petName, s.ownerFirst, s.ownerLast] + s.itemNames
            if SearchEngine.matches(trimmed, in: fields) {
                ids.insert(s.id)
                total += s.total
            }
        }
        return (ids, total)
    }
}
