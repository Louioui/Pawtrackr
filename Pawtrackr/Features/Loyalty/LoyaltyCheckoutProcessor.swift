//
//  LoyaltyCheckoutProcessor.swift
//  Pawtrackr
//
//  Single implementation of "award loyalty points for a checkout", shared by
//  both earn paths (CheckoutTransactionActor and LoyaltyService.applyPoints)
//  so tier multipliers, rebook bonuses, and ledger entries can never diverge.
//
//  Synchronous by design: callers are ModelActors and pass their own
//  context-bound models; this never hops isolation and never saves — the
//  caller owns the transaction boundary.
//

import Foundation
import SwiftData

enum LoyaltyCheckoutProcessor {

    /// Computes and applies the visit's earned points (tier multiplier +
    /// rebook bonus), delta-adjusts the client balance so re-processing an
    /// edited checkout is idempotent, and upserts the visit's `.earned`
    /// ledger entry.
    ///
    /// Returns the client UUID when the client balance changed (the caller
    /// records the CloudKit change), or nil when nothing changed.
    @discardableResult
    static func applyEarnings(
        visit: Visit,
        pet: Pet,
        total: Decimal,
        in context: ModelContext,
        now: Date = .now,
        config: LoyaltyConfigSnapshot = .default
    ) -> UUID? {
        let client = pet.owner

        let base = LoyaltyEngine.calculatePoints(for: total, config: config)
        let tier = LoyaltyEngine.tier(
            forLifetimeEarned: LoyaltyEngine.lifetimeEarnedPoints(for: client, excluding: visit.uuid)
        )
        let bonus = LoyaltyEngine.rebookBonus(
            previousVisitEndedAt: LoyaltyEngine.previousCompletedVisitDate(for: client, excluding: visit.uuid),
            checkoutAt: now,
            basePoints: base
        )
        let points = LoyaltyEngine.earnedPoints(base: base, tier: tier) + bonus

        let previousPoints = visit.loyaltyPointsChange
        guard points != previousPoints else { return nil }

        visit.loyaltyPointsChange = points
        visit.updatedAt = .now
        visit.lastModifiedAt = .now
        visit.lastModifiedBy = DeviceIdentity.currentID

        guard let client else { return nil }
        client.loyaltyPoints += points - previousPoints
        client.updatedAt = .now
        client.lastModifiedBy = DeviceIdentity.currentID

        upsertEarnedEntry(
            visit: visit,
            client: client,
            pet: pet,
            points: points,
            in: context
        )
        return client.uuid
    }

    /// One `.earned` ledger row per visit: a re-processed checkout (edited
    /// total) updates the existing entry instead of appending a duplicate.
    private static func upsertEarnedEntry(
        visit: Visit,
        client: Client,
        pet: Pet,
        points: Int,
        in context: ModelContext
    ) {
        let visitUUID = visit.uuid
        let earnedRaw = LoyaltyLedgerEntry.Kind.earned.rawValue
        var descriptor = FetchDescriptor<LoyaltyLedgerEntry>(
            predicate: #Predicate<LoyaltyLedgerEntry> {
                $0.visitUUID == visitUUID && $0.kindRaw == earnedRaw
            }
        )
        descriptor.fetchLimit = 1

        if let existing = (try? context.fetch(descriptor))?.first {
            existing.points = points
            existing.balanceAfter = client.loyaltyPoints
            existing.markModified()
        } else {
            let entry = LoyaltyLedgerEntry(
                kind: .earned,
                points: points,
                clientUUID: client.uuid,
                visitUUID: visitUUID,
                balanceAfter: client.loyaltyPoints,
                reason: pet.name
            )
            context.insert(entry)
        }
    }
}
