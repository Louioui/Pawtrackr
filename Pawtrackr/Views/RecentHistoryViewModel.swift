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
        
        // IMPROVEMENT: Build a smarter predicate to filter as much as possible in the database.
        let predicate = #Predicate<Visit> { visit in
            // Always fetch only completed visits.
            visit.endedAt != nil &&
            
            // Text search condition
            (trimmedQuery.isEmpty ||
             visit.pet.name.localizedStandardContains(trimmedQuery) ||
             (visit.pet.owner?.firstName.localizedStandardContains(trimmedQuery) ?? false) ||
             (visit.pet.owner?.lastName.localizedStandardContains(trimmedQuery) ?? false) ||
             visit.items.filter { item in
                 item.name.localizedStandardContains(trimmedQuery)
             }.isEmpty == false)
        }
        
        do {
            let descriptor = FetchDescriptor<Visit>(predicate: predicate, sortBy: [SortDescriptor(\.sortKeyDate, order: .reverse)])
            var fetchedVisits = try modelContext.fetch(descriptor)
            
            // Perform final date scoping in-memory
            let calendar = Calendar.current
            fetchedVisits = fetchedVisits.filter { visit in
                switch scope {
                case .all:
                    return true
                case .today:
                    return calendar.isDateInToday(visit.sortKeyDate)
                case .thisWeek:
                    return calendar.dateInterval(of: .weekOfYear, for: .now)?.contains(visit.sortKeyDate) ?? false
                }
            }
            
            // Update summary stats
            self.summaryVisitCount = fetchedVisits.count
            let totalRevenue = fetchedVisits.reduce(Decimal.zero) { $0 +~ $1.total }
            self.summaryRevenueString = totalRevenue.moneyString
            
            // Group for the view
            self.groupedVisits = Dictionary(grouping: fetchedVisits, by: { calendar.startOfDay(for: $0.sortKeyDate) })
            self.sortedDays = self.groupedVisits.keys.sorted(by: >)
            
        } catch {
            print("Failed to fetch recent history: \(error)")
        }
        
        self.isLoading = false
    }
    
    func exportCSV() -> String {
        let allVisits = sortedDays.flatMap { groupedVisits[$0] ?? [] }
        var lines: [String] = ["startedAt,endedAt,pet,owner,services,amount,payment,notes"]
        for v in allVisits {
            let started = Formatters.iso8601.string(from: v.startedAt)
            let ended = v.endedAt.map { Formatters.iso8601.string(from: $0) } ?? ""
            let pet = v.pet.name.csvEscaped
            let owner = v.pet.owner?.fullName.csvEscaped ?? ""
            let services = v.items.map { $0.displayName.csvEscaped }.joined(separator: "; ")
            let amount = v.total.moneyString
            let payment = v.payment?.method.displayName.csvEscaped ?? ""
            let notes = v.note?.replacingOccurrences(of: "\n", with: " ").csvEscaped ?? ""
            lines.append("\(started),\(ended),\(pet),\(owner),\(services),\(amount),\(payment),\(notes)")
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
