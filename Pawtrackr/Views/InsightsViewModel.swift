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
    private(set) var packageLeaders: [PackageLeader] = []
    private(set) var categoryTotals: [CategoryTotal] = []
    private(set) var clientLeaders: [ClientLeader] = []
    private(set) var isLoading: Bool = false
    
    // MARK: - Dependencies
    private var modelContext: ModelContext
    private var workSeq: Int = 0 // guards async result application
    private var searchTask: Task<Void, Never>? = nil
    private var notificationToken: NSObjectProtocol?
    // Keep lightweight snapshots for export to avoid retaining large graphs on main
    private var scopedSnaps: [InsightVisitSnap] = []

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        // Refresh when a checkout completes anywhere in the app
        notificationToken = NotificationCenter.default.addObserver(
            forName: .visitDidComplete,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.fetchAndProcessData()
        }
        fetchAndProcessData()
    }
    
    // See note in RecentHistoryViewModel about deinit and actor isolation.
    
    private func scheduleFetch() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
            guard !Task.isCancelled else { return }
            self?.fetchAndProcessData()
        }
    }
    
    // MARK: - Data Processing
    
    func fetchAndProcessData() {
        isLoading = true
        #if DEBUG
        let t0 = Date()
        #endif
        let currentSeq = { workSeq &+= 1; return workSeq }()

        let (start, end) = dateRange(for: scope)
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let needle = trimmedSearch.folding(options: .diacriticInsensitive, locale: .current).lowercased()

        let container = modelContext.container
        Task.detached(priority: .utility) { [currentSeq] in
            // Build predicate for completed visits in optional date range
            let visitPredicate = #Predicate<Visit> { visit in
                visit.endedAt != nil &&
                (start == nil || visit.endedAt! >= start!) &&
                (end == nil || visit.endedAt! <= end!)
            }
            var descriptor = FetchDescriptor<Visit>(predicate: visitPredicate, sortBy: [SortDescriptor(\.endedAt, order: .reverse)])
            // For extremely large datasets, apply a soft cap to keep UI snappy
            if start == nil && end == nil { descriptor.fetchLimit = 5000 }

            let bg = ModelContext(container)
            var visits: [Visit] = []
            do { visits = try bg.fetch(descriptor) } catch { }

            // Map to snapshots off-main
            var snaps: [InsightVisitSnap] = visits.map { v in
                InsightVisitSnap(
                    startedAt: v.startedAt,
                    endedAt: v.endedAt,
                    total: (v.total as NSDecimalNumber).doubleValue,
                    petName: v.pet.name,
                    ownerName: v.pet.owner?.fullName ?? "",
                    itemDisplayNames: v.items.map { $0.displayName },
                    itemServiceCategories: v.items.compactMap { $0.service?.category?.rawValue },
                    paymentMethod: v.payment?.method.displayName,
                    paymentReference: v.payment?.externalReference,
                    note: v.note
                )
            }

            if !needle.isEmpty {
                snaps = snaps.filter { s in
                    func norm(_ s: String) -> String { s.folding(options: .diacriticInsensitive, locale: .current).lowercased() }
                    let pet = norm(s.petName)
                    let owner = norm(s.ownerName)
                    let services = s.itemDisplayNames.map(norm)
                    return pet.contains(needle) || owner.contains(needle) || services.contains { $0.contains(needle) }
                }
            }

            let computed = InsightsComputer.compute(from: snaps)
            await MainActor.run {
                guard currentSeq == self.workSeq else { return }

                self.scopedSnaps = snaps

                let revenueString = Formatters.currency.string(from: NSNumber(value: computed.totalRevenue)) ?? "$0.00"
                let aov = computed.count > 0 ? computed.totalRevenue / Double(computed.count) : 0.0
                let aovString = Formatters.currency.string(from: NSNumber(value: aov)) ?? "$0.00"
                let avgDurationString: String = {
                    guard computed.avgMinutes > 0 else { return "—" }
                    let mins = Int(computed.avgMinutes.rounded())
                    let hrs = mins / 60
                    let rem = mins % 60
                    return hrs > 0 ? "\(hrs)h \(rem)m" : "\(rem)m"
                }()
                self.kpis = KpiSet(revenueString: revenueString, count: computed.count, aovString: aovString, avgDurationString: avgDurationString)
                #if canImport(Charts)
                self.revenueSeries = computed.revenuePerDay.keys.sorted().map { day in
                    let amount = Decimal(computed.revenuePerDay[day] ?? 0)
                    let label = day.formatted(date: .abbreviated, time: .omitted)
                    return RevenuePoint(label: label, date: day, amount: amount)
                }
                #endif
                self.serviceLeaders = computed.serviceCounts.map { ServiceLeader(name: $0.key, count: $0.value) }
                    .sorted { lhs, rhs in
                        if lhs.count == rhs.count { return lhs.name < rhs.name }
                        return lhs.count > rhs.count
                    }
                    .prefix(10).map { $0 }
                self.packageLeaders = computed.packageCounts.map { PackageLeader(name: $0.key, count: $0.value) }
                    .sorted { lhs, rhs in
                        if lhs.count == rhs.count { return lhs.name < rhs.name }
                        return lhs.count > rhs.count
                    }
                self.categoryTotals = computed.categoryCounts.compactMap { (key, value) in
                        Service.Category(rawValue: key).map { CategoryTotal(category: $0, count: value) }
                    }
                    .sorted { lhs, rhs in
                        if lhs.count == rhs.count { return lhs.category.rawValue < rhs.category.rawValue }
                        return lhs.count > rhs.count
                    }
                self.clientLeaders = computed.clientAmounts.sorted { a, b in
                        if a.value == b.value { return a.key < b.key }
                        return a.value > b.value
                    }
                    .prefix(10)
                    .map { (name, amount) in
                        let amt = Formatters.currency.string(from: NSNumber(value: amount)) ?? "$0.00"
                        return ClientLeader(id: name, name: name, amountString: amt)
                    }

                self.isLoading = false
                #if DEBUG
                let dt = Date().timeIntervalSince(t0)
                print("Insights fetch+compute+apply in \(String(format: "%.2f", dt))s for \(snaps.count) visits")
                #endif
            }
        }
    }
    
    var exportCSV: String {
        var lines: [String] = [
            "StartedAt,EndedAt,Pet,Owner,Services,Amount,Payment,Reference,Notes"
        ]
        for s in scopedSnaps {
            let started = Formatters.iso8601.string(from: s.startedAt)
            let ended = s.endedAt.map { Formatters.iso8601.string(from: $0) } ?? ""
            let pet = s.petName.csvEscaped
            let owner = s.ownerName.csvEscaped
            let services = s.itemDisplayNames.map { $0.csvEscaped }.joined(separator: "; ")
            let amount = Formatters.currency.string(from: NSNumber(value: s.total)) ?? "$0.00"
            let payment = (s.paymentMethod ?? "").csvEscaped
            let reference = (s.paymentReference ?? "").csvEscaped
            let notes = (s.note ?? "").replacingOccurrences(of: "\n", with: " ").csvEscaped
            lines.append([started, ended, pet, owner, services, amount, payment, reference, notes].joined(separator: ","))
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
            let day = cal.startOfDay(for: v.endedAt ?? v.startedAt)
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
        var byClient: [String: Totals] = [:]
        for v in visits {
            guard let owner = v.pet.owner else { continue }
            let id = String(describing: owner.persistentModelID)
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

    private func calculatePackageLeaders(from visits: [Visit]) -> [PackageLeader] {
        // Count only services that are part of the Grooming packages
        var counts: [String: Int] = [:]
        for v in visits {
            for item in v.items {
                if let service = item.service, service.category == .groom {
                    counts[service.name, default: 0] += 1
                }
            }
        }
        let rows = counts.map { PackageLeader(name: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count { return lhs.name < rhs.name }
                return lhs.count > rhs.count
            }
        return rows
    }

    private func calculateCategoryTotals(from visits: [Visit]) -> [CategoryTotal] {
        // Totals across all categories for a simple breakdown chart
        var byCategory: [Service.Category: Int] = [:]
        for v in visits {
            for item in v.items {
                if let cat = item.service?.category {
                    byCategory[cat, default: 0] += 1
                }
            }
        }
        let mapped: [CategoryTotal] = byCategory
            .map { CategoryTotal(category: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count { return lhs.category.rawValue < rhs.category.rawValue }
                return lhs.count > rhs.count
            }
        return mapped
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
        let id: String
        let name: String
        let amountString: String
    }

    struct PackageLeader: Identifiable {
        let name: String
        let count: Int
        var id: String { name }
        var countString: String { "\(count)x" }
    }
    
    struct CategoryTotal: Identifiable {
        let category: Service.Category
        let count: Int
        var id: String { category.rawValue }
        var name: String { category.rawValue }
    }
}

private extension Calendar {
    /// End-of-day for a given date (23:59:59 on the same calendar day).
    func endOfDay(for date: Date) -> Date {
        let start = startOfDay(for: date)
        // start of next day minus 1 second to remain inclusive
        return self.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? date
    }
}

// MARK: - Background Compute Helpers
fileprivate struct InsightVisitSnap: Sendable {
    let startedAt: Date
    let endedAt: Date?
    let total: Double
    let petName: String
    let ownerName: String
    let itemDisplayNames: [String]
    let itemServiceCategories: [String]
    let paymentMethod: String?
    let paymentReference: String?
    let note: String?
}

fileprivate struct InsightsComputed: Sendable {
    let totalRevenue: Double
    let count: Int
    let avgMinutes: Double
    let revenuePerDay: [Date: Double]
    let serviceCounts: [String: Int]
    let packageCounts: [String: Int]
    let categoryCounts: [String: Int]
    let clientAmounts: [String: Double]
}

fileprivate enum InsightsComputer {
    static func compute(from snaps: [InsightVisitSnap]) -> InsightsComputed {
        let count = snaps.count

        // Revenue & durations
        var totalRevenue: Double = 0
        var totalDurationSec: Double = 0
        var durationCount = 0

        // Buckets
        var revenuePerDay: [Date: Double] = [:]
        var serviceCounts: [String: Int] = [:]
        var packageCounts: [String: Int] = [:]
        var categoryCounts: [String: Int] = [:]
        var clientAmounts: [String: Double] = [:]

        let cal = Calendar.current

        for v in snaps {
            totalRevenue += v.total
            if let end = v.endedAt {
                totalDurationSec += end.timeIntervalSince(v.startedAt)
                durationCount += 1
                let day = cal.startOfDay(for: end)
                revenuePerDay[day, default: 0] += v.total
            } else {
                let day = cal.startOfDay(for: v.startedAt)
                revenuePerDay[day, default: 0] += v.total
            }

            for name in v.itemDisplayNames { serviceCounts[name, default: 0] += 1 }
            // Treat all service categories as packages for a simple ranking
            for cat in v.itemServiceCategories { packageCounts[cat, default: 0] += 1 }
            for cat in v.itemServiceCategories { categoryCounts[cat, default: 0] += 1 }
            clientAmounts[v.ownerName, default: 0] += v.total
        }

        let avgMinutes = durationCount > 0 ? (totalDurationSec / Double(durationCount)) / 60.0 : 0

        return InsightsComputed(
            totalRevenue: totalRevenue,
            count: count,
            avgMinutes: avgMinutes,
            revenuePerDay: revenuePerDay,
            serviceCounts: serviceCounts,
            packageCounts: packageCounts,
            categoryCounts: categoryCounts,
            clientAmounts: clientAmounts
        )
    }
}
