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
    static func rebuildDay(for date: Date, in context: ModelContext) {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return }
        do {
            // Fetch all visits and filter in memory to avoid SwiftData predicate capture issues
            let allVisits = try context.fetch(FetchDescriptor<Visit>())
            let visits = allVisits.filter { visit in
                guard let endedAt = visit.endedAt else { return false }
                return endedAt >= start && endedAt < end
            }
            let count = visits.count
            let visitRevenue = visits.reduce(Decimal.zero) { $0 +~ $1.total }

            // Payments are optional—prefer visit totals and only fall back to payments if needed.
            let allPayments = try context.fetch(FetchDescriptor<Payment>())
            let payments = allPayments.filter { $0.paidAt >= start && $0.paidAt < end }
            let paymentRevenue = payments.reduce(Decimal.zero) { $0 +~ $1.amount }
            let revenue = visitRevenue > .zero ? visitRevenue : paymentRevenue

            // Upsert DaySummary - fetch all and filter in memory
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

            for (name, count) in svcCounts {
                if let summary = existingSvcDict[name] {
                    summary.count = count
                    existingSvcDict.removeValue(forKey: name)
                } else {
                    context.insert(ServiceDaySummary(day: start, serviceName: name, count: count))
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

            let allCatSummaries = try context.fetch(FetchDescriptor<CategoryDaySummary>())
            let existingCat = allCatSummaries.filter { cal.isDate($0.day, inSameDayAs: start) }
            var existingCatDict = existingCat.reduce(into: [String: CategoryDaySummary]()) { $0[$1.categoryRaw] = $1 }

            for (raw, count) in catCounts {
                if let summary = existingCatDict[raw] {
                    summary.count = count
                    existingCatDict.removeValue(forKey: raw)
                } else {
                    context.insert(CategoryDaySummary(day: start, categoryRaw: raw, count: count))
                }
            }

            for summary in existingCatDict.values {
                context.delete(summary)
            }

            try context.save()
            Logger.summaries.info("Summary rebuilt for \(start, privacy: .public): \(count) visits, \(revenue) revenue")
        } catch {
            Logger.summaries.error("Summary rebuild failed for \(start, privacy: .public): \(String(describing: error))")
        }
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
