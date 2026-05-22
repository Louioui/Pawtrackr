//
//  CloudSyncReconciler.swift
//  Pawtrackr
//
//  Conservative cleanup after CloudKit imports.
//

import Foundation
import SwiftData
import OSLog

enum CloudSyncReconciler {
    struct Report: Sendable {
        let duplicateCheckoutTransactionsRemoved: Int
        let duplicateVisitsRemoved: Int
        let orphanVisitItemCount: Int
        let orphanPaymentCount: Int

        var summary: String {
            var parts: [String] = []
            if duplicateCheckoutTransactionsRemoved > 0 {
                parts.append("removed \(duplicateCheckoutTransactionsRemoved) duplicate checkout transaction(s)")
            }
            if duplicateVisitsRemoved > 0 {
                parts.append("merged \(duplicateVisitsRemoved) duplicate visit(s)")
            }
            if orphanVisitItemCount > 0 {
                parts.append("found \(orphanVisitItemCount) orphan visit item(s)")
            }
            if orphanPaymentCount > 0 {
                parts.append("found \(orphanPaymentCount) orphan payment(s)")
            }
            return parts.isEmpty ? "Cloud import reconciliation found no issues" : "Cloud import reconciliation " + parts.joined(separator: ", ")
        }
    }

    static func reconcileImportedData(in context: ModelContext) -> Report {
        var removedTransactions = 0
        var removedVisits = 0
        var orphanItems = 0
        var orphanPayments = 0

        do {
            try reconcileConcurrentEdits(in: context)
            removedTransactions = try dedupeCheckoutTransactions(in: context)
            removedVisits = try dedupeVisits(in: context)
            orphanItems = try countOrphanVisitItems(in: context)
            orphanPayments = try countOrphanPayments(in: context)

            if context.hasChanges {
                try context.save()
            }
        } catch {
            Logger.cloudReconcile.error("Cloud import reconciliation failed: \(error.localizedDescription, privacy: .public)")
        }

        return Report(
            duplicateCheckoutTransactionsRemoved: removedTransactions,
            duplicateVisitsRemoved: removedVisits,
            orphanVisitItemCount: orphanItems,
            orphanPaymentCount: orphanPayments
        )
    }

    private static func reconcileConcurrentEdits(in context: ModelContext) throws {
        // Find Clients and Pets that were recently updated and check for version drifts
        let clientRows = try context.fetch(FetchDescriptor<Client>())
        let clientGroups = Dictionary(grouping: clientRows) { $0.uuid }
        for (_, group) in clientGroups where group.count > 1 {
            let sorted = group.sorted { $0.updatedAt > $1.updatedAt }
            let winner = sorted.first!
            let losers = sorted.dropFirst()
            for loser in losers {
                winner.resolveConflict(with: loser)
                context.delete(loser)
            }
        }

        let petRows = try context.fetch(FetchDescriptor<Pet>())
        let petGroups = Dictionary(grouping: petRows) { $0.uuid }
        for (_, group) in petGroups where group.count > 1 {
            let sorted = group.sorted { $0.updatedAt > $1.updatedAt }
            let winner = sorted.first!
            let losers = sorted.dropFirst()
            for loser in losers {
                winner.resolveConflict(with: loser)
                context.delete(loser)
            }
        }
    }

    private static func dedupeVisits(in context: ModelContext) throws -> Int {
        // Fetch all active visits (or recently started ones)
        var descriptor = FetchDescriptor<Visit>(
            predicate: #Predicate { $0.endedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .forward)]
        )
        descriptor.relationshipKeyPathsForPrefetching = [\Visit.pet]
        let activeVisits = try context.fetch(descriptor)
        
        // Group by deterministic visit session token first, then pet UUID, to
        // collapse simultaneous shop check-ins without relying on CloudKit
        // unique constraints.
        let groups = Dictionary(grouping: activeVisits) { visit -> String in
            let token = visit.sessionToken.trimmingCharacters(in: .whitespacesAndNewlines)
            if !token.isEmpty { return token }
            if let petUUID = visit.pet?.uuid { return "pet:\(petUUID.uuidString)" }
            return "visit:\(visit.uuid.uuidString)"
        }
        var removed = 0
        
        for (_, visits) in groups where visits.count > 1 {
            // Sort by creation or update time to find the 'canonical' one
            let sorted = visits.sorted { $0.createdAt < $1.createdAt }
            let canonical = sorted.first!
            let duplicates = sorted.dropFirst()
            
            for dupe in duplicates {
                // If they started within 5 minutes of each other, they are likely duplicates
                let diff = abs(dupe.startedAt.timeIntervalSince(canonical.startedAt))
                if diff < 300 { // 5 minutes
                    mergeVisit(dupe, into: canonical)
                    context.delete(dupe)
                    removed += 1

                    if let pet = canonical.pet?.uuid {
                        Task { @MainActor in
                            CloudKitMonitor.shared.warmMediaCache(for: pet)
                        }
                    }
                }
            }
        }
        return removed
    }

    private static func dedupeCheckoutTransactions(in context: ModelContext) throws -> Int {
        let rows = try context.fetch(FetchDescriptor<CheckoutTransaction>())
        let groups = Dictionary(grouping: rows) { $0.idempotencyKey }
        var removed = 0

        for (key, transactions) in groups where !key.isEmpty && transactions.count > 1 {
            let canonical = transactions.max { lhs, rhs in
                if lhs.status.rank != rhs.status.rank {
                    return lhs.status.rank < rhs.status.rank
                }
                return lhs.updatedAt < rhs.updatedAt
            }

            for transaction in transactions where transaction !== canonical {
                context.delete(transaction)
                removed += 1
            }
        }

        return removed
    }

    private static func mergeVisit(_ source: Visit, into target: Visit) {
        target.ensureSessionToken()
        if target.startedAt > source.startedAt {
            target.startedAt = source.startedAt
        }
        if target.endedAt == nil {
            target.endedAt = source.endedAt
        }
        if target.total == .zero, source.total > .zero {
            target.total = source.total
        }
        if target.payment == nil, let payment = source.payment {
            target.attachPayment(payment)
        }

        target.note = mergedText(target.note, source.note)
        target.behaviorTags = mergedTags(target.behaviorTags, source.behaviorTags)

        if target.beforePhotoData == nil { target.beforePhotoData = source.beforePhotoData }
        if target.beforeThumbnailData == nil { target.beforeThumbnailData = source.beforeThumbnailData }
        if target.afterPhotoData == nil { target.afterPhotoData = source.afterPhotoData }
        if target.afterThumbnailData == nil { target.afterThumbnailData = source.afterThumbnailData }

        if let sourceItems = source.items, !sourceItems.isEmpty {
            let existingKeys = Set((target.items ?? []).map { lineItemKey($0) })
            for item in sourceItems where !existingKeys.contains(lineItemKey(item)) {
                item.visit = target
            }
        }
        target.lastModifiedAt = max(target.lastModifiedAt, source.lastModifiedAt)
        target.updatedAt = max(target.updatedAt, source.updatedAt)
    }

    private static func mergedText(_ lhs: String?, _ rhs: String?) -> String? {
        let left = lhs?.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = rhs?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let right, !right.isEmpty else { return left?.isEmpty == false ? left : nil }
        guard let left, !left.isEmpty else { return right }
        if left == right || left.contains(right) { return left }
        if right.contains(left) { return right }
        return "\(left)\n---\n\(right)"
    }

    private static func mergedTags(_ lhs: [String], _ rhs: [String]) -> [String] {
        Array(Set((lhs + rhs).map { $0.trimmed }.filter { !$0.isEmpty }))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private static func lineItemKey(_ item: VisitItem) -> String {
        let serviceKey = item.service?.uuid.uuidString ?? item.name.lowercased()
        return "\(serviceKey)|\(item.quantity)|\(item.unitPrice)"
    }

    private static func countOrphanVisitItems(in context: ModelContext) throws -> Int {
        let rows = try context.fetch(FetchDescriptor<VisitItem>())
        return rows.filter { $0.visit == nil }.count
    }

    private static func countOrphanPayments(in context: ModelContext) throws -> Int {
        let rows = try context.fetch(FetchDescriptor<Payment>())
        return rows.filter { $0.visit == nil }.count
    }
}

private extension CheckoutTransaction.Status {
    var rank: Int {
        switch self {
        case .succeeded: return 3
        case .processing: return 2
        case .failed: return 1
        }
    }
}

private extension Logger {
    static let cloudReconcile = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr",
        category: "CloudReconcile"
    )
}
