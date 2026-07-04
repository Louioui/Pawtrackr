//
//  Migrations.swift
//  Pawtrackr
//
//  Schema migration plan and one-time data seeding/coercion.
//

import Foundation
import SwiftData
import OSLog

// MARK: - Schema Versions
//
// Schemas are versioned so existing users' on-disk stores can be migrated
// safely when we change models. The pattern:
//
//   1. Each shipped schema is a frozen `VersionedSchema` enum (V1, V2, ...).
//   2. The newest one is aliased to `PawtrackrSchema` so the rest of the
//      codebase always points at "current".
//   3. `PawtrackrMigrationPlan.schemas` lists every version that has ever
//      shipped, in order.
//   4. For each transition between versions, add a `MigrationStage` —
//      `.lightweight` for purely additive changes, `.custom` for renames /
//      type changes / data backfills.
//
// When you change a model:
//   - If the change is a property addition with a default → still V1
//     compatible (lightweight). Bump the version's patch number.
//   - If the change renames a property, deletes one, or changes a type →
//     define V2 below, change the typealias, and add a custom stage.
//
// IMPORTANT: never delete a version once it has shipped to users; it must
// remain in the chain so their store can climb forward to the latest.

/// Always points at the most recent shipped schema. The rest of the app
/// references this name; only the migration plan distinguishes versions.
typealias PawtrackrSchema = PawtrackrSchemaV2

enum PawtrackrSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version = .init(1, 0, 7)

    static var models: [any PersistentModel.Type] {
        [
            Client.self, Pet.self, Visit.self, VisitItem.self, Service.self, Payment.self, User.self,
            DaySummary.self, ServiceDaySummary.self, CategoryDaySummary.self, ClientInsightSummary.self,
            CheckoutTransaction.self, EmergencyContact.self, BusinessConfig.self, MessageTemplate.self,
            InventoryItem.self, InventoryTransaction.self, DeviceMetadata.self, PresenceRecord.self,
            LoyaltyLedgerEntry.self
        ]
    }
}

enum PawtrackrSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version = .init(1, 1, 0)

    static var models: [any PersistentModel.Type] {
        PawtrackrSchemaV1.models + [
            LoyaltyConfig.self,
            LoyaltyRewardTemplate.self
        ]
    }
}

// MARK: - Migration Plan

enum PawtrackrMigrationPlan: SchemaMigrationPlan {
    /// Ordered list of every schema we've ever shipped. Append new versions;
    /// never remove or reorder.
    static var schemas: [any VersionedSchema.Type] {
        [PawtrackrSchemaV1.self, PawtrackrSchemaV2.self]
    }

    /// Transitions between adjacent schema versions.
    static var stages: [MigrationStage] {
        [
            .lightweight(
                fromVersion: PawtrackrSchemaV1.self,
                toVersion: PawtrackrSchemaV2.self
            )
        ]
    }
}


// MARK: - Data Seeding & Coercion

enum DataMigrations {
    static func backfillVisitSessionTokens(in context: ModelContext) {
        do {
            let visits = try context.fetch(FetchDescriptor<Visit>())
            var updates = 0
            for visit in visits where visit.sessionToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                visit.ensureSessionToken()
                updates += 1
            }
            if context.hasChanges {
                try context.save()
            }
            if updates > 0 {
                Logger.migrations.info("Backfilled \(updates) visit session token(s).")
            }
        } catch {
            Logger.migrations.error("Visit session token backfill failed: \(String(describing: error))")
        }
    }

    static func coercePets(in context: ModelContext) {
        do {
            let sortDescriptors = [SortDescriptor(\Pet.createdAt, order: .forward)]
            let batchSize = 500
            var offset = 0
            var updates = 0

            while true {
                var descriptor = FetchDescriptor<Pet>(sortBy: sortDescriptors)
                descriptor.fetchLimit = batchSize
                descriptor.fetchOffset = offset

                let pets = try context.fetch(descriptor)
                if pets.isEmpty { break }

                var batchChanged = false
                for pet in pets {
                    var changed = false
                    // Species is already constrained to .dog/.cat at type level now.
                    // Gender: ensure either .male or .female. If not, default to .male.
                    if pet.gender != .male && pet.gender != .female {
                        pet.gender = .male
                        changed = true
                    }

                    if changed { updates += 1; batchChanged = true }
                }

                if batchChanged {
                    try context.save()
                }

                offset += pets.count
            }

            if updates > 0 {
                Logger.migrations.info("Coerced \(updates) pet records for narrowed enums.")
            }
        } catch {
            Logger.migrations.error("Migration failed: \(String(describing: error))")
        }
    }



    /// Build or refresh DaySummary rows from existing completed visits.
    /// Safe to run multiple times; it re-computes aggregates per distinct day.
    static func backfillDaySummaries(in context: ModelContext) {
        do {
            let completedDesc = FetchDescriptor<Visit>(
                predicate: #Predicate { $0.endedAt != nil },
                sortBy: [SortDescriptor(\.endedAt, order: .forward)]
            )
            let visits = try context.fetch(completedDesc)
            let cal = Calendar.current
            var byDay: [Date: (Decimal, Int)] = [:]
            for v in visits {
                guard let end = v.endedAt else { continue }
                let day = cal.startOfDay(for: end)
                var agg = byDay[day] ?? (.zero, 0)
                agg.0 += v.total
                agg.1 += 1
                byDay[day] = agg
            }

            SummaryUpdater.dedupeSummaryCaches(in: context)

            // Fetch existing summaries to upsert
            let existing = try context.fetch(FetchDescriptor<DaySummary>())
            let index = SummaryUpdater.collapsedDayAggregates(from: existing)
            var rowsByDay: [Date: DaySummary] = [:]
            for row in existing where index[row.day] != nil {
                if let current = rowsByDay[row.day] {
                    if row.visitCount > current.visitCount ||
                        (row.visitCount == current.visitCount && row.revenue > current.revenue) {
                        rowsByDay[row.day] = row
                    }
                } else {
                    rowsByDay[row.day] = row
                }
            }

            var updated = 0, inserted = 0
            for (day, (rev, cnt)) in byDay {
                if let s = rowsByDay[day] {
                    if s.revenue != rev || s.visitCount != cnt { s.revenue = rev; s.visitCount = cnt; updated += 1 }
                } else {
                    context.insert(DaySummary(day: day, revenue: rev, visitCount: cnt)); inserted += 1
                }
            }
            if inserted + updated > 0 { try context.save() }
            Logger.migrations.info("DaySummary backfill: inserted=\(inserted), updated=\(updated)")
        } catch {
            Logger.migrations.error("DaySummary backfill failed: \(String(describing: error))")
        }
    }

    /// Ensure the service catalog exists with the current set of packages/add-ons,
    /// and strip any default prices so checkout amounts are always user-entered.
    static func ensureServiceCatalog(in context: ModelContext) {
        let desired = DefaultServiceCatalog.definitions

        do {
            let existing = try context.fetch(FetchDescriptor<Service>())
            var byName: [String: Service] = [:]
            existing.forEach { byName[$0.name.lowercased()] = $0 }
            let knownNamesByEnglishName = DefaultServiceCatalog.allKnownLocalizedNamesByEnglishName

            for def in desired {
                let targetName = def.localizedName
                let candidateNames = knownNamesByEnglishName[def.englishName] ?? [def.englishName.lowercased()]
                let svc = candidateNames.compactMap { byName[$0] }.first

                if let svc {
                    // Normalize attributes and remove any default price.
                    if svc.name != targetName {
                        svc.rename(targetName)
                    }
                    svc.setCategory(def.category)
                    svc.setSystemIcon(def.icon)
                    svc.setBasePrice(nil)
                    svc.setEnabled(true)
                    svc.isPackage = def.isPackage
                } else {
                    let svc = Service(
                        name: targetName,
                        category: def.category,
                        systemIcon: def.icon,
                        basePrice: nil,
                        isEnabled: true,
                        isPackage: def.isPackage
                    )
                    context.insert(svc)
                }
            }

            for svc in existing where svc.isObsoleteCheckoutService {
                svc.setEnabled(false)
                svc.setBasePrice(nil)
            }

            // Persist any updates/inserts.
            if context.hasChanges {
                try context.save()
            }
        } catch {
            Logger.migrations.error("ensureServiceCatalog failed: \(String(describing: error))")
        }
    }

    /// Backfill `.earned` loyalty ledger entries for visits that awarded points
    /// before the ledger existed, and collapse cross-device backfill duplicates
    /// (two devices can each run this once; CloudKit then merges both sets).
    /// Idempotent: keyed by visit UUID, safe to run on every launch.
    static func backfillLoyaltyLedger(in context: ModelContext) {
        do {
            let earnedRaw = LoyaltyLedgerEntry.Kind.earned.rawValue
            let earnedEntries = try context.fetch(
                FetchDescriptor<LoyaltyLedgerEntry>(
                    predicate: #Predicate<LoyaltyLedgerEntry> { $0.kindRaw == earnedRaw }
                )
            )

            // Dedupe: keep the earliest-created entry per visit.
            var byVisit: [UUID: LoyaltyLedgerEntry] = [:]
            var removed = 0
            for entry in earnedEntries {
                guard let visitUUID = entry.visitUUID else { continue }
                if let kept = byVisit[visitUUID] {
                    let loser = entry.createdAt < kept.createdAt ? kept : entry
                    let winner = entry.createdAt < kept.createdAt ? entry : kept
                    byVisit[visitUUID] = winner
                    context.delete(loser)
                    removed += 1
                } else {
                    byVisit[visitUUID] = entry
                }
            }

            // Backfill pre-ledger visit earns. Historical balances are unknowable,
            // so `balanceAfter` stays nil on backfilled rows.
            let visits = try context.fetch(
                FetchDescriptor<Visit>(predicate: #Predicate<Visit> { $0.loyaltyPointsChange != 0 })
            )
            var inserted = 0
            for visit in visits where byVisit[visit.uuid] == nil {
                guard let client = visit.pet?.owner else { continue }
                let entry = LoyaltyLedgerEntry(
                    kind: .earned,
                    points: visit.loyaltyPointsChange,
                    clientUUID: client.uuid,
                    visitUUID: visit.uuid,
                    balanceAfter: nil,
                    reason: visit.pet?.name,
                    createdAt: visit.endedAt ?? visit.startedAt
                )
                context.insert(entry)
                byVisit[visit.uuid] = entry
                inserted += 1
            }

            if context.hasChanges {
                try context.save()
            }
            if inserted > 0 || removed > 0 {
                Logger.migrations.info("Loyalty ledger backfill: inserted=\(inserted), dedupedAway=\(removed)")
            }
        } catch {
            Logger.migrations.error("Loyalty ledger backfill failed: \(String(describing: error))")
        }
    }

    static func ensureMessageTemplates(in context: ModelContext) {
        do {
            let existing = try context.fetch(FetchDescriptor<MessageTemplate>())
            let existingTitles = Set(
                existing.map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            )
            var inserted = false
            for template in MessageTemplate.defaults {
                let key = template.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !existingTitles.contains(key) {
                    context.insert(template)
                    inserted = true
                }
            }
            if inserted {
                try context.save()
            }
        } catch {
            Logger.migrations.error("ensureMessageTemplates failed: \(String(describing: error))")
        }
    }

    static func ensureLoyaltyDefaults(in context: ModelContext) {
        do {
            var didChange = false

            let configDescriptor = FetchDescriptor<LoyaltyConfig>(
                sortBy: [SortDescriptor(\.createdAt, order: .forward)]
            )
            let configs = try context.fetch(configDescriptor)
            if configs.isEmpty {
                context.insert(LoyaltyConfig())
                didChange = true
            } else if configs.count > 1 {
                didChange = collapseDuplicateLoyaltyConfigs(configs, in: context)
            }

            let existingRewards = try context.fetch(FetchDescriptor<LoyaltyRewardTemplate>())
            let existingTitles = Set(
                existingRewards.map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            )
            for template in LoyaltyRewardTemplate.seedTemplates() {
                let key = template.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !existingTitles.contains(key) {
                    context.insert(template)
                    didChange = true
                }
            }

            if didChange || context.hasChanges {
                try context.save()
            }
        } catch {
            Logger.migrations.error("ensureLoyaltyDefaults failed: \(String(describing: error))")
        }
    }

    /// Merges duplicate loyalty settings field-by-field before deleting extras.
    private static func collapseDuplicateLoyaltyConfigs(_ configs: [LoyaltyConfig], in context: ModelContext) -> Bool {
        guard configs.count > 1 else { return false }

        let canonical = configs.min { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.updatedAt < rhs.updatedAt
        } ?? configs[0]
        let defaults = LoyaltyConfigSnapshot.default
        let newestFirst = configs.sorted { lhs, rhs in
            loyaltyConfigIsNewer(lhs, than: rhs)
        }

        if let earnMode = newestFirst.first(where: { $0.earnMode != defaults.earnMode })?.earnMode,
           canonical.earnMode != earnMode {
            canonical.setEarnMode(earnMode)
        }
        if let pointsPerDollar = newestFirst.first(where: { $0.pointsPerDollar != defaults.pointsPerDollar })?.pointsPerDollar,
           canonical.pointsPerDollar != pointsPerDollar {
            canonical.setPointsPerDollar(pointsPerDollar)
        }
        if let pointsPerVisit = newestFirst.first(where: { $0.pointsPerVisit != defaults.pointsPerVisit })?.pointsPerVisit,
           canonical.pointsPerVisit != pointsPerVisit {
            canonical.setPointsPerVisit(pointsPerVisit)
        }
        if let redemptionThreshold = newestFirst.first(where: { $0.redemptionThreshold != defaults.redemptionThreshold })?.redemptionThreshold,
           canonical.redemptionThreshold != redemptionThreshold {
            canonical.setRedemptionThreshold(redemptionThreshold)
        }
        if let isRewardsCatalogEnabled = newestFirst.first(where: { $0.isRewardsCatalogEnabled != defaults.isRewardsCatalogEnabled })?.isRewardsCatalogEnabled,
           canonical.isRewardsCatalogEnabled != isRewardsCatalogEnabled {
            canonical.setRewardsCatalogEnabled(isRewardsCatalogEnabled)
        }

        for duplicate in configs where duplicate !== canonical {
            context.delete(duplicate)
        }
        canonical.markModified()
        return true
    }

    /// Orders loyalty settings so reconciliation prefers the most recent field source.
    private static func loyaltyConfigIsNewer(_ lhs: LoyaltyConfig, than rhs: LoyaltyConfig) -> Bool {
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }
        return lhs.createdAt > rhs.createdAt
    }
}

extension Logger {
    static let migrations = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "migrations")
}
