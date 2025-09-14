//
//  SummaryUpdater.swift
//  Pawtrackr
//
//  Utilities to maintain DaySummary aggregates.
//

import Foundation
import SwiftData

enum SummaryUpdater {
    /// Recalculate the DaySummary for the calendar day that contains `date`.
    static func rebuildDay(for date: Date, in context: ModelContext) {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return }
        do {
            let desc = FetchDescriptor<Visit>(
                predicate: #Predicate { $0.endedAt != nil && $0.endedAt! >= start && $0.endedAt! < end }
            )
            let visits = try context.fetch(desc)
            var revenue: Decimal = .zero
            for v in visits { revenue += v.total }
            let count = visits.count

            // Upsert DaySummary
            let existing = try context.fetch(FetchDescriptor<DaySummary>(predicate: #Predicate { $0.day == start }))
            if let s = existing.first {
                s.revenue = revenue
                s.visitCount = count
            } else {
                context.insert(DaySummary(day: start, revenue: revenue, visitCount: count))
            }
            // Rebuild per-service counts
            let existingSvc = try context.fetch(FetchDescriptor<ServiceDaySummary>(predicate: #Predicate { $0.day == start }))
            for s in existingSvc { context.delete(s) }
            var svcCounts: [String: Int] = [:]
            for v in visits {
                for item in v.items { svcCounts[item.displayName, default: 0] += 1 }
            }
            for (name, c) in svcCounts { context.insert(ServiceDaySummary(day: start, serviceName: name, count: c)) }

            // Rebuild per-category counts
            let existingCat = try context.fetch(FetchDescriptor<CategoryDaySummary>(predicate: #Predicate { $0.day == start }))
            for s in existingCat { context.delete(s) }
            var catCounts: [String: Int] = [:]
            for v in visits {
                for item in v.items {
                    if let raw = item.service?.category?.rawValue {
                        catCounts[raw, default: 0] += 1
                    }
                }
            }
            for (raw, c) in catCounts { context.insert(CategoryDaySummary(day: start, categoryRaw: raw, count: c)) }

            try context.save()
        } catch {
            // Best-effort; do not crash if summaries fail to update.
        }
    }
}
