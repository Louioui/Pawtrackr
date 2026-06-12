//
//  DataReset.swift
//  Pawtrackr
//
//  "Start Fresh" support. Erases operational business records while preserving
//  the user's setup so a new operator can move from the guided demo into real
//  use with one tap.
//

import Foundation
import SwiftData
import OSLog

/// Erases operational records ("Start Fresh") while preserving setup. The Service
/// catalog, `BusinessConfig`, message templates, and device/sync identity all
/// survive — only the data a user accumulates (clients, pets, visits, payments,
/// inventory, checkout ledger, analytics rollups) is removed.
///
/// There is no `isDemo` marker on any model, so demo and real rows are
/// indistinguishable: this is necessarily a *full* operational wipe, not a
/// demo-only one. Deletions are logical (`context.delete`), which
/// `NSPersistentCloudKitContainer` exports as tombstones — so the wipe
/// propagates to iCloud and every signed-in device. That is intentional, but it
/// is why the calling UI must gate it behind an explicit, destructive
/// confirmation.
@MainActor
enum DataReset {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "DataReset")

    /// Deletes all operational data via the main context. Children are removed
    /// through SwiftData cascade rules (`Client → Pet → Visit → VisitItem/Payment`
    /// and `EmergencyContact`; `InventoryItem → InventoryTransaction`), so only
    /// cascade roots plus the standalone rollup/ledger models are deleted here.
    static func wipeOperationalData(in context: ModelContext) throws {
        try deleteAll(Client.self, in: context)          // cascades pets/visits/items/payments/contacts
        try deleteAll(InventoryItem.self, in: context)   // cascades inventory transactions

        // Standalone models not reached by any cascade.
        try deleteAll(CheckoutTransaction.self, in: context)
        try deleteAll(DaySummary.self, in: context)
        try deleteAll(ServiceDaySummary.self, in: context)
        try deleteAll(CategoryDaySummary.self, in: context)
        try deleteAll(ClientInsightSummary.self, in: context)

        if context.hasChanges {
            try context.save()
        }

        // Spotlight entries created on client/pet mutations now point at deleted
        // records — clear the index so stale search results don't linger.
        SpotlightIndexer.shared.reindexAll()
        log.info("Start Fresh: operational data wiped (catalog + business config preserved).")
    }

    private static func deleteAll<T: PersistentModel>(_ type: T.Type, in context: ModelContext) throws {
        let objects = try context.fetch(FetchDescriptor<T>())
        for object in objects {
            context.delete(object)
        }
    }
}
