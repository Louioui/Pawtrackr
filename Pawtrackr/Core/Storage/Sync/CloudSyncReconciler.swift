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
        /// Client / pet UUIDs that exist more than once. Reported, never merged:
        /// see `countDuplicateClientsAndPets`.
        var duplicateClientGroups: Int = 0
        var duplicatePetGroups: Int = 0

        var summary: String {
            // Shown in Salon Activity, so every part is localized.
            var parts: [String] = []
            if duplicateCheckoutTransactionsRemoved > 0 {
                parts.append(String(
                    format: AppLocalization.localized(
                        "cloudkit.reconcile.duplicate_transactions_fmt",
                        value: "duplicate checkout transactions removed: %d"
                    ),
                    duplicateCheckoutTransactionsRemoved
                ))
            }
            if duplicateVisitsRemoved > 0 {
                parts.append(String(
                    format: AppLocalization.localized(
                        "cloudkit.reconcile.duplicate_visits_fmt",
                        value: "duplicate visits merged: %d"
                    ),
                    duplicateVisitsRemoved
                ))
            }
            if orphanVisitItemCount > 0 {
                parts.append(String(
                    format: AppLocalization.localized(
                        "cloudkit.reconcile.orphan_items_fmt",
                        value: "visit services without a visit: %d"
                    ),
                    orphanVisitItemCount
                ))
            }
            if orphanPaymentCount > 0 {
                parts.append(String(
                    format: AppLocalization.localized(
                        "cloudkit.reconcile.orphan_payments_fmt",
                        value: "payments without a visit: %d"
                    ),
                    orphanPaymentCount
                ))
            }
            if duplicateClientGroups > 0 || duplicatePetGroups > 0 {
                parts.append(String(
                    format: AppLocalization.localized(
                        "cloudkit.reconcile.duplicate_records_fmt",
                        value: "duplicated clients: %1$d, duplicated pets: %2$d, left in place"
                    ),
                    duplicateClientGroups,
                    duplicatePetGroups
                ))
            }
            guard !parts.isEmpty else {
                return AppLocalization.localized(
                    "cloudkit.reconcile.no_issues",
                    value: "Checked the iCloud download and found no issues"
                )
            }
            return String(
                format: AppLocalization.localized(
                    "cloudkit.reconcile.summary_fmt",
                    value: "Checked the iCloud download: %@"
                ),
                parts.joined(separator: "; ")
            )
        }
    }

    static func reconcileImportedData(in context: ModelContext) -> Report {
        var removedTransactions = 0
        var removedVisits = 0
        var orphanItems = 0
        var orphanPayments = 0
        var duplicates = (clients: 0, pets: 0)

        do {
            duplicates = try countDuplicateClientsAndPets(in: context)
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
            orphanPaymentCount: orphanPayments,
            duplicateClientGroups: duplicates.clients,
            duplicatePetGroups: duplicates.pets
        )
    }

    /// Clients and pets that share a UUID are counted and logged, never merged.
    ///
    /// This used to keep the newest twin and `context.delete` the other, which
    /// cascade-deleted that twin's pets, visits and payments on every device —
    /// and it copied the older twin's fields over the newer one. Twins come
    /// from one object being re-uploaded, so they share `createdAt` and differ
    /// only in editable fields; two devices mid-sync can pick different
    /// survivors, delete each other's, and cascade away everything. Nothing
    /// that deterministic exists to choose by, so a duplicate row on screen is
    /// the safe outcome.
    private static func countDuplicateClientsAndPets(in context: ModelContext) throws -> (clients: Int, pets: Int) {
        let clientGroups = Dictionary(grouping: try context.fetch(FetchDescriptor<Client>()), by: \.uuid)
            .values.filter { $0.count > 1 }.count
        let petGroups = Dictionary(grouping: try context.fetch(FetchDescriptor<Pet>()), by: \.uuid)
            .values.filter { $0.count > 1 }.count
        if clientGroups + petGroups > 0 {
            Logger.cloudReconcile.notice("Duplicate UUIDs after import: \(clientGroups) client group(s), \(petGroups) pet group(s); left in place.")
        }
        return (clientGroups, petGroups)
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
                    // Save the moves before deleting: the delete cascades to
                    // whatever is still attached to the duplicate.
                    try context.save()
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
            source.payment = nil
            target.attachPayment(payment)
        }

        target.note = mergedText(target.note, source.note)
        target.behaviorTags = mergedTags(target.behaviorTags, source.behaviorTags)

        if target.beforePhotoData == nil { target.beforePhotoData = source.beforePhotoData }
        if target.beforeThumbnailData == nil { target.beforeThumbnailData = source.beforeThumbnailData }
        if target.afterPhotoData == nil { target.afterPhotoData = source.afterPhotoData }
        if target.afterThumbnailData == nil { target.afterThumbnailData = source.afterThumbnailData }

        if let sourceItems = source.items, !sourceItems.isEmpty {
            // Move by swapping the to-many collections. Setting only
            // `item.visit` doesn't reliably take the item out of the source's
            // `items`, and the source's cascade delete then destroys it.
            let existingKeys = Set((target.items ?? []).map { lineItemKey($0) })
            let moving = sourceItems.filter { !existingKeys.contains(lineItemKey($0)) }
            let movingIDs = Set(moving.map(\.persistentModelID))
            source.items = sourceItems.filter { !movingIDs.contains($0.persistentModelID) }
            target.items = (target.items ?? []) + moving
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
