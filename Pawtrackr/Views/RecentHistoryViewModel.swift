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
    private var searchTask: Task<Void, Never>? = nil

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        fetchVisits()
    }

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
            (start == nil || visit.sortKeyDate >= start!) &&
            (end == nil || visit.sortKeyDate < end!)
        }
        
        do {
            let descriptor = FetchDescriptor<Visit>(predicate: predicate, sortBy: [SortDescriptor(\.sortKeyDate, order: .reverse)])
            var fetchedVisits = try modelContext.fetch(descriptor)

            // Apply text search in-memory (SwiftData predicate DSL can't use nested closures)
            if !trimmedQuery.isEmpty {
                fetchedVisits = fetchedVisits.filter { v in
                    if v.pet.name.localizedStandardContains(trimmedQuery) { return true }
                    if let owner = v.pet.owner {
                        if owner.firstName.localizedStandardContains(trimmedQuery) { return true }
                        if owner.lastName.localizedStandardContains(trimmedQuery) { return true }
                    }
                    if v.items.contains(where: { $0.name.localizedStandardContains(trimmedQuery) }) { return true }
                    return false
                }
            }
            
            // Group for the view based on start of day
            let calendar = Calendar.current
            
            // Update summary stats
            self.summaryVisitCount = fetchedVisits.count
            let totalRevenue = fetchedVisits.reduce(Decimal.zero) { $0 +~ $1.total }
            self.summaryRevenueString = totalRevenue.moneyString
            
            self.groupedVisits = Dictionary(grouping: fetchedVisits, by: { calendar.startOfDay(for: $0.sortKeyDate) })
            self.sortedDays = self.groupedVisits.keys.sorted(by: >)
            
        } catch {
            print("Failed to fetch recent history: \(error)")
        }
        
        self.isLoading = false
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
