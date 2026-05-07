//
//  SummaryUpdater.swift
//  Pawtrackr
//
//  Utilities to maintain DaySummary aggregates.
//

import Foundation
import SwiftData
import OSLog

enum SummaryUpdater {
    struct DayAggregate: Equatable {
        let day: Date
        let revenue: Decimal
        let visitCount: Int
    }

    static func collapsedDayAggregates(from summaries: [DaySummary]) -> [Date: DayAggregate] {
        summaries.reduce(into: [Date: DayAggregate]()) { result, summary in
            let candidate = DayAggregate(day: summary.day, revenue: summary.revenue, visitCount: summary.visitCount)
            guard let existing = result[summary.day] else {
                result[summary.day] = candidate
                return
            }
            if isPreferred(candidate, over: existing) {
                result[summary.day] = candidate
            }
        }
    }

    static func collapsedServiceCounts(from summaries: [ServiceDaySummary]) -> [String: Int] {
        let perDayAndService = summaries.reduce(into: [SummaryNameKey: Int]()) { result, summary in
            let key = SummaryNameKey(day: summary.day, name: summary.serviceName)
            result[key] = max(result[key] ?? 0, summary.count)
        }
        return perDayAndService.reduce(into: [String: Int]()) { result, entry in
            result[entry.key.name, default: 0] += entry.value
        }
    }

    static func collapsedCategoryCounts(from summaries: [CategoryDaySummary]) -> [String: Int] {
        let perDayAndCategory = summaries.reduce(into: [SummaryNameKey: Int]()) { result, summary in
            let key = SummaryNameKey(day: summary.day, name: summary.categoryRaw)
            result[key] = max(result[key] ?? 0, summary.count)
        }
        return perDayAndCategory.reduce(into: [String: Int]()) { result, entry in
            result[entry.key.name, default: 0] += entry.value
        }
    }

    /// Recalculate the DaySummary for the calendar day that contains `date`.
    /// Optimized to fetch only the data needed for the specific day.
    static func rebuildDay(for date: Date, in context: ModelContext) {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return }

        do {
            // Fetch only visits that ended on this specific day
            let visits = try fetchVisitsEndedInRange(start: start, end: end, in: context)
            let count = visits.count
            
            // Primary revenue source: Sum of completed visit totals.
            // Fallback: Sum of payments for the day if no visits are found (e.g. legacy or unlinked payments).
            var revenue = visits.reduce(Decimal.zero) { $0 +~ $1.total }
            if revenue == .zero {
                let payments = try fetchPaymentsInRange(start: start, end: end, in: context)
                revenue = payments.reduce(Decimal.zero) { $0 +~ $1.amount }
            }

            // Upsert DaySummary - fetch only for this day
            let existingSummaries = try fetchDaySummaries(for: start, in: context)
            let existingSummary = canonicalDaySummary(from: existingSummaries, in: context)
            if let s = existingSummary {
                s.revenue = revenue
                s.visitCount = count
            } else {
                context.insert(DaySummary(day: start, revenue: revenue, visitCount: count))
            }

            // Rebuild per-service counts
            var svcCounts: [String: Int] = [:]
            for v in visits {
                for item in v.items ?? [] { svcCounts[item.displayName, default: 0] += 1 }
            }

            let existingSvc = try fetchServiceDaySummaries(for: start, in: context)
            var existingSvcDict = canonicalServiceSummaries(from: existingSvc, in: context)

            for (name, svcCount) in svcCounts {
                if let summary = existingSvcDict[name] {
                    summary.count = svcCount
                    existingSvcDict.removeValue(forKey: name)
                } else {
                    context.insert(ServiceDaySummary(day: start, serviceName: name, count: svcCount))
                }
            }

            for summary in existingSvcDict.values {
                context.delete(summary)
            }

            // Rebuild per-category counts
            var catCounts: [String: Int] = [:]
            for v in visits {
                for item in v.items ?? [] {
                    if let raw = item.serviceCategoryRaw ?? item.service?.category?.rawValue {
                        catCounts[raw, default: 0] += 1
                    }
                }
            }

            let existingCat = try fetchCategoryDaySummaries(for: start, in: context)
            var existingCatDict = canonicalCategorySummaries(from: existingCat, in: context)

            for (raw, catCount) in catCounts {
                if let summary = existingCatDict[raw] {
                    summary.count = catCount
                    existingCatDict.removeValue(forKey: raw)
                } else {
                    context.insert(CategoryDaySummary(day: start, categoryRaw: raw, count: catCount))
                }
            }

            for summary in existingCatDict.values {
                context.delete(summary)
            }

            if context.hasChanges {
                try context.save()
            }
            Logger.summaries.info("Summary rebuilt for \(start, privacy: .public): \(count) visits, \(revenue) revenue")
        } catch {
            Logger.summaries.error("Summary rebuild failed for \(start, privacy: .public): \(String(describing: error))")
        }
    }

    /// Deletes duplicate CloudKit-imported cache rows. The summaries are
    /// derived data, so for duplicate keys we keep the highest-count/highest-
    /// revenue row until the next rebuild can recompute from visits.
    static func dedupeSummaryCaches(in context: ModelContext) {
        do {
            let dayRows = try context.fetch(FetchDescriptor<DaySummary>())
            _ = canonicalDaySummaries(from: dayRows, in: context)

            let serviceRows = try context.fetch(FetchDescriptor<ServiceDaySummary>())
            _ = canonicalServiceSummariesByDayAndName(from: serviceRows, in: context)

            let categoryRows = try context.fetch(FetchDescriptor<CategoryDaySummary>())
            _ = canonicalCategorySummariesByDayAndName(from: categoryRows, in: context)

            if context.hasChanges {
                try context.save()
            }
        } catch {
            Logger.summaries.error("Summary cache de-dupe failed: \(String(describing: error))")
        }
    }

    // MARK: - Optimized Fetch Helpers

    private static func fetchVisitsEndedInRange(start: Date, end: Date, in context: ModelContext) throws -> [Visit] {
        // SwiftData #Predicate supports date comparisons. Using a precise predicate 
        // ensures the database (SQLite) does the heavy lifting, not the main CPU.
        let descriptor = FetchDescriptor<Visit>(
            predicate: #Predicate<Visit> { v in
                if let ended = v.endedAt {
                    return ended >= start && ended < end
                } else {
                    return false
                }
            }
        )
        return try context.fetch(descriptor)
    }

    private static func fetchPaymentsInRange(start: Date, end: Date, in context: ModelContext) throws -> [Payment] {
        let descriptor = FetchDescriptor<Payment>(
            predicate: #Predicate<Payment> { p in
                p.paidAt >= start && p.paidAt < end
            }
        )
        return try context.fetch(descriptor)
    }

    private static func fetchDaySummaries(for day: Date, in context: ModelContext) throws -> [DaySummary] {
        let descriptor = FetchDescriptor<DaySummary>(
            predicate: #Predicate<DaySummary> { $0.day == day }
        )
        return try context.fetch(descriptor)
    }

    private static func fetchServiceDaySummaries(for day: Date, in context: ModelContext) throws -> [ServiceDaySummary] {
        let descriptor = FetchDescriptor<ServiceDaySummary>(
            predicate: #Predicate<ServiceDaySummary> { $0.day == day }
        )
        return try context.fetch(descriptor)
    }

    private static func fetchCategoryDaySummaries(for day: Date, in context: ModelContext) throws -> [CategoryDaySummary] {
        let descriptor = FetchDescriptor<CategoryDaySummary>(
            predicate: #Predicate<CategoryDaySummary> { $0.day == day }
        )
        return try context.fetch(descriptor)
    }

    /// Rebuild summaries only for days that have changed since the last sync.
    /// Call this once on app launch.
    static func rebuildAllSummaries(in context: ModelContext) {
        let lastSync = UserDefaults.standard.object(forKey: "lastSummarySyncDate") as? Date ?? .distantPast
        let now = Date()
        
        do {
            // Fetch visits updated since last sync
            let descriptor = FetchDescriptor<Visit>(
                predicate: #Predicate<Visit> { $0.updatedAt > lastSync }
            )
            let changedVisits = try context.fetch(descriptor)
            
            if changedVisits.isEmpty {
                Logger.summaries.info("No visits changed since \(lastSync), skipping full rebuild")
                UserDefaults.standard.set(now, forKey: "lastSummarySyncDate")
                return
            }

            // Get unique days from changed visits
            let cal = Calendar.current
            var uniqueDays = Set<Date>()
            for visit in changedVisits {
                if let endedAt = visit.endedAt {
                    uniqueDays.insert(cal.startOfDay(for: endedAt))
                }
                // Also rebuild the day it started if it was recently updated (e.g. checked in)
                uniqueDays.insert(cal.startOfDay(for: visit.startedAt))
            }

            Logger.summaries.info("Rebuilding summaries for \(uniqueDays.count) changed days")

            // Rebuild each changed day
            for day in uniqueDays {
                rebuildDay(for: day, in: context)
            }

            UserDefaults.standard.set(now, forKey: "lastSummarySyncDate")
            Logger.summaries.info("Incremental summary rebuild successful")
        } catch {
            Logger.summaries.error("Incremental summary rebuild failed: \(String(describing: error))")
        }
    }

    /// Synchronous version that reuses already-fetched visits for efficiency
    private static func rebuildDaySync(
        for date: Date, 
        allVisits: [Visit], 
        existingSummary: DaySummary?,
        existingServiceSummaries: [ServiceDaySummary],
        in context: ModelContext
    ) {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return }

        // Filter visits for this day
        let visits = allVisits.filter { visit in
            guard let endedAt = visit.endedAt else { return false }
            return endedAt >= start && endedAt < end
        }
        let count = visits.count
        let revenue = visits.reduce(Decimal.zero) { $0 +~ $1.total }

        // Upsert DaySummary
        if let s = existingSummary {
            s.revenue = revenue
            s.visitCount = count
        } else {
            context.insert(DaySummary(day: start, revenue: revenue, visitCount: count))
        }

        // Rebuild per-service counts
        var svcCounts: [String: Int] = [:]
        for v in visits {
            for item in v.items ?? [] { svcCounts[item.displayName, default: 0] += 1 }
        }

        var existingSvcDict = existingServiceSummaries.reduce(into: [String: ServiceDaySummary]()) { $0[$1.serviceName] = $1 }

        for (name, svcCount) in svcCounts {
            if let summary = existingSvcDict[name] {
                summary.count = svcCount
                existingSvcDict.removeValue(forKey: name)
            } else {
                context.insert(ServiceDaySummary(day: start, serviceName: name, count: svcCount))
            }
        }

        for summary in existingSvcDict.values {
            context.delete(summary)
        }
    }

    private struct SummaryNameKey: Hashable {
        let day: Date
        let name: String
    }

    private static func isPreferred(_ candidate: DayAggregate, over existing: DayAggregate) -> Bool {
        if candidate.visitCount != existing.visitCount {
            return candidate.visitCount > existing.visitCount
        }
        return candidate.revenue > existing.revenue
    }

    private static func isPreferred(_ candidate: DaySummary, over existing: DaySummary) -> Bool {
        if candidate.visitCount != existing.visitCount {
            return candidate.visitCount > existing.visitCount
        }
        return candidate.revenue > existing.revenue
    }

    private static func canonicalDaySummary(from summaries: [DaySummary], in context: ModelContext) -> DaySummary? {
        canonicalDaySummaries(from: summaries, in: context).values.first
    }

    private static func canonicalDaySummaries(from summaries: [DaySummary], in context: ModelContext) -> [Date: DaySummary] {
        var result: [Date: DaySummary] = [:]
        for summary in summaries {
            if let existing = result[summary.day] {
                if isPreferred(summary, over: existing) {
                    context.delete(existing)
                    result[summary.day] = summary
                } else {
                    context.delete(summary)
                }
            } else {
                result[summary.day] = summary
            }
        }
        return result
    }

    private static func canonicalServiceSummaries(from summaries: [ServiceDaySummary], in context: ModelContext) -> [String: ServiceDaySummary] {
        var result: [String: ServiceDaySummary] = [:]
        for summary in summaries {
            if let existing = result[summary.serviceName] {
                if summary.count > existing.count {
                    context.delete(existing)
                    result[summary.serviceName] = summary
                } else {
                    context.delete(summary)
                }
            } else {
                result[summary.serviceName] = summary
            }
        }
        return result
    }

    private static func canonicalCategorySummaries(from summaries: [CategoryDaySummary], in context: ModelContext) -> [String: CategoryDaySummary] {
        var result: [String: CategoryDaySummary] = [:]
        for summary in summaries {
            if let existing = result[summary.categoryRaw] {
                if summary.count > existing.count {
                    context.delete(existing)
                    result[summary.categoryRaw] = summary
                } else {
                    context.delete(summary)
                }
            } else {
                result[summary.categoryRaw] = summary
            }
        }
        return result
    }

    private static func canonicalServiceSummariesByDayAndName(from summaries: [ServiceDaySummary], in context: ModelContext) -> [SummaryNameKey: ServiceDaySummary] {
        var result: [SummaryNameKey: ServiceDaySummary] = [:]
        for summary in summaries {
            let key = SummaryNameKey(day: summary.day, name: summary.serviceName)
            if let existing = result[key] {
                if summary.count > existing.count {
                    context.delete(existing)
                    result[key] = summary
                } else {
                    context.delete(summary)
                }
            } else {
                result[key] = summary
            }
        }
        return result
    }

    private static func canonicalCategorySummariesByDayAndName(from summaries: [CategoryDaySummary], in context: ModelContext) -> [SummaryNameKey: CategoryDaySummary] {
        var result: [SummaryNameKey: CategoryDaySummary] = [:]
        for summary in summaries {
            let key = SummaryNameKey(day: summary.day, name: summary.categoryRaw)
            if let existing = result[key] {
                if summary.count > existing.count {
                    context.delete(existing)
                    result[key] = summary
                } else {
                    context.delete(summary)
                }
            } else {
                result[key] = summary
            }
        }
        return result
    }
}

private extension Logger {
    static let summaries = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "summaries")
}
