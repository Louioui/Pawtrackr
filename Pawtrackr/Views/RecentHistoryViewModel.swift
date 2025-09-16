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
        ) { [weak self] note in
            guard let self else { return }
            guard let metadata = note.visitDidCompleteMetadata else {
                self.fetchVisits()
                return
            }

            if let ended = metadata.endedAt, !self.scope.contains(date: ended) {
                return
            }
            if !metadata.matchesSearchQuery(self.query) {
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
    
    private func scheduleFetch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300)) // Debounce search
            guard !Task.isCancelled else { return }
            self.fetchVisits()
        }
    }
    
    func fetchVisits(focusingOn _: Set<UUID> = []) {
        self.isLoading = true
        #if DEBUG
        let t0 = Date()
        #endif
        let currentSeq = { workSeq &+= 1; return workSeq }()

        do {
            let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let tokens = Self.tokens(for: trimmedQuery)
            let bounds = scope.dateBounds()
            var filter = VisitHistoryFilter(startDate: bounds.start, endDate: bounds.end, searchTokens: tokens)
            filter.fetchLimit = scope.preferredFetchLimit
            let descriptor = VisitHistoryFetchDescriptorBuilder.makeDescriptor(using: filter)
            let fetchedVisits = try modelContext.fetch(descriptor)

            Task.detached(priority: .utility) { [currentSeq, fetchedVisits] in
                let calendar = Calendar.current
                let grouped = Dictionary(grouping: fetchedVisits, by: { calendar.startOfDay(for: $0.endedAt ?? $0.startedAt) })
                let sortedDays = grouped.keys.sorted(by: >)
                let totalRevenue = fetchedVisits.reduce(Decimal.zero) { partial, visit in
                    partial +~ visit.total
                }
                await MainActor.run {
                    guard currentSeq == self.workSeq else { return }
                    self.summaryVisitCount = fetchedVisits.count
                    self.summaryRevenueString = totalRevenue.moneyString
                    self.groupedVisits = grouped
                    self.sortedDays = sortedDays
                    self.isLoading = false
                    #if DEBUG
                    let dt = Date().timeIntervalSince(t0)
                    print("History fetch+group in \(String(format: "%.2f", dt))s for \(fetchedVisits.count) visits")
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
        case all = "All"
        case today = "Today"
        case thisWeek = "This Week"

        var id: String { rawValue }

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
            }
        }

        func contains(date: Date, referenceDate: Date = .now, calendar: Calendar = .current) -> Bool {
            if self == .all { return true }
            let bounds = dateBounds(referenceDate: referenceDate, calendar: calendar)
            if let start = bounds.start, date < start { return false }
            if let end = bounds.end, date >= end { return false }
            return true
        }

        var preferredFetchLimit: Int? {
            switch self {
            case .all:
                return 2000
            case .thisWeek:
                return 750
            case .today:
                return nil
            }
        }
    }

    static func tokens(for query: String) -> [String] {
        query
            .split(whereSeparator: { $0.isWhitespace })
            .map { String($0) }
    }
}
