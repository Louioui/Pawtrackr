//
//  InsightsViewModel.swift
//  Pawtrackr
//
//  Created by Assistant on 2025-08-28.
//

import SwiftUI
import SwiftData
#if canImport(Charts)
import Charts
#endif

@Observable
@MainActor
final class InsightsViewModel {
    // MARK: - State
    var scope: Scope = .week { didSet { scheduleFetch() } }
    var customStartDate: Date = .now.addingTimeInterval(-7 * 24 * 60 * 60) { didSet { scheduleFetch() } }
    var customEndDate: Date = .now { didSet { scheduleFetch() } }
    var searchText: String = "" { didSet { scheduleFetch() } }

    // MARK: - Published Data
    private(set) var kpis: KpiSet = .empty
    #if canImport(Charts)
    private(set) var revenueSeries: [RevenuePoint] = []
    #endif
    private(set) var serviceLeaders: [ServiceLeader] = []
    private(set) var clientLeaders: [ClientLeader] = []
    private(set) var isLoading: Bool = false
    
    // MARK: - Dependencies
    private var modelContext: ModelContext
    private var searchTask: Task<Void, Never>? = nil
    private var scopedVisits: [Visit] = []

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        fetchAndProcessData()
    }
    
    private func scheduleFetch() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
            guard !Task.isCancelled else { return }
            await self?.fetchAndProcessData()
        }
    }
    
    // MARK: - Data Processing
    
    func fetchAndProcessData() {
        isLoading = true
        
        let (start, end) = dateRange(for: scope)
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let needle = trimmedSearch.folding(options: .diacriticInsensitive, locale: .current).lowercased()
        
        // Build a predicate only for completion and date range filtering
        let visitPredicate = #Predicate<Visit> { visit in
            visit.endedAt != nil &&
            (start == nil || visit.sortKeyDate >= start!) &&
            (end == nil || visit.sortKeyDate <= end!)
        }
        
        let descriptor = FetchDescriptor<Visit>(predicate: visitPredicate, sortBy: [SortDescriptor(\.sortKeyDate, order: .reverse)])
        
        do {
            scopedVisits = try modelContext.fetch(descriptor)
            
            if !needle.isEmpty {
                scopedVisits = scopedVisits.filter { v in
                    let pet = v.pet.name.folding(options: .diacriticInsensitive, locale: .current).lowercased()
                    let ownerFirst = v.pet.owner?.firstName.folding(options: .diacriticInsensitive, locale: .current).lowercased() ?? ""
                    let ownerLast  = v.pet.owner?.lastName.folding(options: .diacriticInsensitive, locale: .current).lowercased() ?? ""
                    let services = v.items.map { $0.displayName.folding(options: .diacriticInsensitive, locale: .current).lowercased() }
                    return pet.contains(needle) || ownerFirst.contains(needle) || ownerLast.contains(needle) || services.contains { $0.contains(needle) }
                }
            }
            
            // Once we have the filtered data, compute all aggregations
            self.kpis = calculateKpis(from: scopedVisits)
            #if canImport(Charts)
            self.revenueSeries = calculateRevenueSeries(from: scopedVisits)
            #endif
            self.serviceLeaders = calculateServiceLeaders(from: scopedVisits)
            self.clientLeaders = calculateClientLeaders(from: scopedVisits)
            
        } catch {
            print("Failed to fetch or process insights data: \(error)")
        }
        
        isLoading = false
    }
    
    var exportCSV: String {
        // ... CSV generation logic remains the same, but uses `scopedVisits`
        var lines: [String] = ["startedAt,endedAt,pet,owner,services,amount,payment,notes"]
        for v in scopedVisits {
            // (Same CSV line generation as before)
            let started = Formatters.iso8601.string(from: v.startedAt)
            let ended = v.endedAt.map { Formatters.iso8601.string(from: $0) } ?? ""
            let pet = v.pet.name.csvEscaped
            let owner = v.pet.owner?.fullName.csvEscaped ?? ""
            let services = v.items.map { $0.displayName.csvEscaped }.joined(separator: "; ")
            let amount = Formatters.currency.string(from: NSDecimalNumber(decimal: v.total)) ?? "$0.00"
            let payment = v.payment?.method.displayName.csvEscaped ?? ""
            let notes = v.note?.replacingOccurrences(of: "\n", with: " ").csvEscaped ?? ""
            lines.append([started, ended, pet, owner, services, amount, payment, notes].joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }
    
    // MARK: - Calculation Helpers
    
    private func dateRange(for scope: Scope) -> (Date?, Date?) {
        let now = Date()
        let cal = Calendar.current
        switch scope {
        case .today:
            return (cal.startOfDay(for: now), now)
        case .week:
            let startOfWeek = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
            return (startOfWeek, now)
        case .month:
            let startOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: now))!
            return (startOfMonth, now)
        case .all:
            return (nil, nil)
        case .custom:
            return (cal.startOfDay(for: customStartDate), cal.endOfDay(for: customEndDate))
        }
    }
    
    // All calculation functions are now private and take the visits array as an argument
    private func calculateKpis(from visits: [Visit]) -> KpiSet {
        var total: Decimal = 0
        var durations: [TimeInterval] = []
        for v in visits {
            total += v.total
            if let end = v.endedAt { durations.append(end.timeIntervalSince(v.startedAt)) }
        }

        // Revenue & AOV
        let revenueString = Formatters.currency.string(from: NSDecimalNumber(decimal: total)) ?? "$0.00"
        let count = visits.count
        let aov: Decimal = count > 0 ? (total / Decimal(count)) : 0
        let aovString = Formatters.currency.string(from: NSDecimalNumber(decimal: aov)) ?? "$0.00"

        // Average duration (hh mm)
        let avgDurationString: String = {
            guard !durations.isEmpty else { return "—" }
            let avg = durations.reduce(0, +) / Double(durations.count)
            let minutes = Int(avg / 60)
            let hrs = minutes / 60
            let mins = minutes % 60
            if hrs > 0 { return "\(hrs)h \(mins)m" } else { return "\(mins)m" }
        }()

        return KpiSet(revenueString: revenueString, count: count, aovString: aovString, avgDurationString: avgDurationString)
    }
    #if canImport(Charts)
    private func calculateRevenueSeries(from visits: [Visit]) -> [RevenuePoint] {
        guard !visits.isEmpty else { return [] }
        let cal = Calendar.current
        var buckets: [Date: Decimal] = [:]
        for v in visits {
            let day = cal.startOfDay(for: v.sortKeyDate)
            buckets[day, default: 0] += v.total
        }
        let points = buckets.keys.sorted().map { day -> RevenuePoint in
            let amount = buckets[day] ?? 0
            let label = day.formatted(date: .abbreviated, time: .omitted)
            return RevenuePoint(label: label, date: day, amount: amount)
        }
        return points
    }
    #endif
    private func calculateServiceLeaders(from visits: [Visit]) -> [ServiceLeader] {
        var counts: [String: Int] = [:]
        for v in visits {
            for item in v.items { counts[item.displayName, default: 0] += 1 }
        }
        let rows = counts.map { ServiceLeader(name: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count { return lhs.name < rhs.name }
                return lhs.count > rhs.count
            }
        return Array(rows.prefix(10))
    }

    private func calculateClientLeaders(from visits: [Visit]) -> [ClientLeader] {
        struct Totals { var name: String; var amount: Decimal }
        var byClient: [PersistentIdentifier: Totals] = [:]
        for v in visits {
            guard let owner = v.pet.owner else { continue }
            let id = owner.persistentModelID
            var entry = byClient[id] ?? Totals(name: owner.fullName, amount: 0)
            entry.amount += v.total
            byClient[id] = entry
        }
        let sorted = byClient.sorted { a, b in
            if a.value.amount == b.value.amount { return a.value.name < b.value.name }
            return a.value.amount > b.value.amount
        }
        let leaders: [ClientLeader] = sorted.prefix(10).map { (id, totals) in
            let amt = Formatters.currency.string(from: NSDecimalNumber(decimal: totals.amount)) ?? "$0.00"
            return ClientLeader(id: id, name: totals.name, amountString: amt)
        }
        return leaders
    }
}

// MARK: - Data Structures
extension InsightsViewModel {
    enum Scope: String, CaseIterable, Identifiable {
        case today, week, month, all, custom
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    struct KpiSet {
        let revenueString: String
        let count: Int
        let aovString: String
        let avgDurationString: String
        static let empty = KpiSet(revenueString: "$0.00", count: 0, aovString: "$0.00", avgDurationString: "—")
    }

    #if canImport(Charts)
    struct RevenuePoint: Identifiable {
        let label: String
        let date: Date
        let amount: Decimal
        var id: Date { date }
    }
    #endif
    
    struct ServiceLeader: Identifiable {
        let name: String
        let count: Int
        var id: String { name }
        var countString: String { "\(count)x" }
    }
    
    struct ClientLeader: Identifiable {
        let id: PersistentIdentifier
        let name: String
        let amountString: String
    }
}
