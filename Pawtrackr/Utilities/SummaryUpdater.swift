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
            let visitRevenue = visits.reduce(Decimal.zero) { $0 +~ $1.total }

            // Fetch only payments for this day if needed
            let revenue: Decimal
            if visitRevenue > .zero {
                revenue = visitRevenue
            } else {
                let payments = try fetchPaymentsInRange(start: start, end: end, in: context)
                revenue = payments.reduce(Decimal.zero) { $0 +~ $1.amount }
            }

            // Upsert DaySummary - fetch only for this day
            let existingSummary = try fetchDaySummary(for: start, in: context)
            if let s = existingSummary {
                s.revenue = revenue
                s.visitCount = count
            } else {
                context.insert(DaySummary(day: start, revenue: revenue, visitCount: count))
            }

            // Rebuild per-service counts
            var svcCounts: [String: Int] = [:]
            for v in visits {
                for item in v.items { svcCounts[item.displayName, default: 0] += 1 }
            }

            let existingSvc = try fetchServiceDaySummaries(for: start, in: context)
            var existingSvcDict = existingSvc.reduce(into: [String: ServiceDaySummary]()) { $0[$1.serviceName] = $1 }

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
                for item in v.items {
                    if let raw = item.service?.category?.rawValue {
                        catCounts[raw, default: 0] += 1
                    }
                }
            }

            let existingCat = try fetchCategoryDaySummaries(for: start, in: context)
            var existingCatDict = existingCat.reduce(into: [String: CategoryDaySummary]()) { $0[$1.categoryRaw] = $1 }

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

    // MARK: - Optimized Fetch Helpers

    private static func fetchVisitsEndedInRange(start: Date, end: Date, in context: ModelContext) throws -> [Visit] {
        let descriptor = FetchDescriptor<Visit>(
            predicate: #Predicate<Visit> {
                $0.endedAt != nil &&
                $0.endedAt! >= start &&
                $0.endedAt! < end
            }
        )
        return try context.fetch(descriptor)
    }

    private static func fetchPaymentsInRange(start: Date, end: Date, in context: ModelContext) throws -> [Payment] {
        let descriptor = FetchDescriptor<Payment>(
            predicate: #Predicate<Payment> {
                $0.paidAt >= start &&
                $0.paidAt < end
            }
        )
        return try context.fetch(descriptor)
    }

    private static func fetchDaySummary(for day: Date, in context: ModelContext) throws -> DaySummary? {
        let descriptor = FetchDescriptor<DaySummary>(
            predicate: #Predicate<DaySummary> { $0.day == day }
        )
        return try context.fetch(descriptor).first
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

    /// Rebuild summaries for all days that have completed visits.
    /// Call this once on app launch to ensure historical data is captured.
    @MainActor
    static func rebuildAllSummaries(in context: ModelContext) {
        do {
            // Fetch all completed visits
            let allVisits = try context.fetch(FetchDescriptor<Visit>())
            let completedVisits = allVisits.filter { $0.endedAt != nil }

            // Get unique days
            let cal = Calendar.current
            var uniqueDays = Set<Date>()
            for visit in completedVisits {
                if let endedAt = visit.endedAt {
                    uniqueDays.insert(cal.startOfDay(for: endedAt))
                }
            }

            Logger.summaries.info("Rebuilding summaries for \(uniqueDays.count) unique days")

            // Rebuild each day
            for day in uniqueDays {
                rebuildDaySync(for: day, allVisits: completedVisits, in: context)
            }

            try context.save()
            Logger.summaries.info("All summaries rebuilt successfully")
        } catch {
            Logger.summaries.error("Failed to rebuild all summaries: \(String(describing: error))")
        }
    }

    /// Synchronous version that reuses already-fetched visits for efficiency
    private static func rebuildDaySync(for date: Date, allVisits: [Visit], in context: ModelContext) {
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

        do {
            // Upsert DaySummary
            let allDaySummaries = try context.fetch(FetchDescriptor<DaySummary>())
            let existing = allDaySummaries.filter { cal.isDate($0.day, inSameDayAs: start) }
            if let s = existing.first {
                s.revenue = revenue
                s.visitCount = count
            } else {
                context.insert(DaySummary(day: start, revenue: revenue, visitCount: count))
            }

            // Rebuild per-service counts
            var svcCounts: [String: Int] = [:]
            for v in visits {
                for item in v.items { svcCounts[item.displayName, default: 0] += 1 }
            }

            let allServiceSummaries = try context.fetch(FetchDescriptor<ServiceDaySummary>())
            let existingSvc = allServiceSummaries.filter { cal.isDate($0.day, inSameDayAs: start) }
            var existingSvcDict = existingSvc.reduce(into: [String: ServiceDaySummary]()) { $0[$1.serviceName] = $1 }

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
        } catch {
            Logger.summaries.error("rebuildDaySync failed for \(start): \(String(describing: error))")
        }
    }
}

private extension Logger {
    static let summaries = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "summaries")
}
