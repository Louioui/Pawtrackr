//
//  SummaryUpdater.swift
//  Pawtrackr
//
//  Utilities to maintain DaySummary aggregates.
//

import Foundation
import SwiftData
import OSLog
import OSLog

enum SummaryUpdater {
    /// Recalculate the DaySummary for the calendar day that contains `date`.
    static func rebuildDay(for date: Date, in context: ModelContext) {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return }
        do {
            // Calculate revenue from payments
            let paymentDesc = FetchDescriptor<Payment>(
                predicate: #Predicate { $0.paidAt >= start && $0.paidAt < end }
            )
            let payments = try context.fetch(paymentDesc)
            let revenue = payments.reduce(Decimal.zero) { $0 +~ $1.amount }

            // Calculate visit count and get visits for service/category counts
            let visitDesc = FetchDescriptor<Visit>(
                predicate: #Predicate { visit in
                    visit.endedAt != nil ? (visit.endedAt! >= start && visit.endedAt! < end) : false
                }
            )
            let visits = try context.fetch(visitDesc)
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
            var svcCounts: [String: Int] = [:]
            for v in visits {
                for item in v.items { svcCounts[item.displayName, default: 0] += 1 }
            }
            
            let existingSvc = try context.fetch(FetchDescriptor<ServiceDaySummary>(predicate: #Predicate { $0.day == start }))
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
            
            let existingCat = try context.fetch(FetchDescriptor<CategoryDaySummary>(predicate: #Predicate { $0.day == start }))
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
        } catch {
            Logger.summaries.error("Summary rebuild failed for \(start, privacy: .public): \(String(describing: error))")
        }
    }
}

private extension Logger {
    static let summaries = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "summaries")
}
