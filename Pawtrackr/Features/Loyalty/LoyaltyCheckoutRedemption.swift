//
//  LoyaltyCheckoutRedemption.swift
//  Pawtrackr
//
//  Spending a reward as part of a checkout. The view model prices the reward
//  and sends this snapshot with the CheckoutRequest; CheckoutTransactionActor
//  deducts the points in the same save as the payment, so a checkout and its
//  redemption land together or not at all.
//

import Foundation
import SwiftData

/// The reward a checkout spends, as priced on the Payment step. Plain values,
/// so it crosses from the main actor to the transaction actor safely.
struct CheckoutRewardRedemption: Equatable, Sendable {
    let rewardID: String
    let title: String
    let pointCost: Int
    /// What the reward took off the services, already subtracted from the
    /// request's `amount`. Kept for the ledger reason and the receipt.
    let discount: Decimal
}

extension LoyaltyCheckoutProcessor {
    /// Whether the client can pay `redemption` from their balance, counting
    /// points this visit already spent on it (a retried checkout). Call it
    /// before changing anything, so a short balance fails the checkout clean.
    static func canAfford(_ redemption: CheckoutRewardRedemption, client: Client, visitUUID: UUID, in context: ModelContext) -> Bool {
        let alreadySpent = -(redeemedEntry(visitUUID: visitUUID, in: context)?.points ?? 0)
        return client.loyaltyPoints + alreadySpent >= redemption.pointCost
    }

    /// Makes the visit's `.redeemed` ledger row match `redemption`: one row per
    /// visit, the client balance moved by the difference only, so processing
    /// the same checkout twice spends the points once. A nil redemption
    /// refunds and removes a row an earlier attempt left behind.
    ///
    /// Returns true when the client balance changed; the caller saves.
    @discardableResult
    static func applyRedemption(
        _ redemption: CheckoutRewardRedemption?,
        visitUUID: UUID,
        client: Client,
        in context: ModelContext
    ) -> Bool {
        let existing = redeemedEntry(visitUUID: visitUUID, in: context)
        let previousCost = -(existing?.points ?? 0)
        let newCost = redemption?.pointCost ?? 0
        guard newCost != previousCost || existing?.reason != redemption?.title else { return false }

        client.loyaltyPoints = max(0, client.loyaltyPoints + previousCost - newCost)
        client.updatedAt = .now
        client.lastModifiedBy = DeviceIdentity.currentID

        if let redemption {
            if let existing {
                existing.points = -redemption.pointCost
                existing.balanceAfter = client.loyaltyPoints
                existing.reason = redemption.title
                existing.markModified()
            } else {
                context.insert(LoyaltyLedgerEntry(
                    kind: .redeemed,
                    points: -redemption.pointCost,
                    clientUUID: client.uuid,
                    visitUUID: visitUUID,
                    balanceAfter: client.loyaltyPoints,
                    reason: redemption.title
                ))
            }
        } else if let existing {
            context.delete(existing)
        }
        return newCost != previousCost
    }

    private static func redeemedEntry(visitUUID: UUID, in context: ModelContext) -> LoyaltyLedgerEntry? {
        let redeemedRaw = LoyaltyLedgerEntry.Kind.redeemed.rawValue
        var descriptor = FetchDescriptor<LoyaltyLedgerEntry>(
            predicate: #Predicate<LoyaltyLedgerEntry> {
                $0.visitUUID == visitUUID && $0.kindRaw == redeemedRaw
            }
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }
}
