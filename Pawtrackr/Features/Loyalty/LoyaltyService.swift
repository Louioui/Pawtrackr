import Foundation
import SwiftData

@ModelActor
actor LoyaltyService {

    /// Applies checkout-earned loyalty points to the visit's owning client.
    /// Delegates to LoyaltyCheckoutProcessor so this path and
    /// CheckoutTransactionActor award identical points (tier multiplier +
    /// rebook bonus) and stay idempotent on re-processing.
    func applyPoints(for visit: Visit) async throws {
        guard let pet = visit.pet else { return }

        let config = LoyaltyConfigResolver.snapshot(in: modelContext)
        let clientUUID = LoyaltyCheckoutProcessor.applyEarnings(
            visit: visit,
            pet: pet,
            total: visit.total,
            in: modelContext,
            now: visit.endedAt ?? .now,
            config: config
        )
        guard clientUUID != nil, let client = pet.owner else { return }

        try modelContext.save()
        await recordClientChange(
            operation: "Applied loyalty points",
            client: client,
            changedKeys: ["loyaltyPoints", "updatedAt", "lastModifiedBy"]
        )
    }

    /// Redeems points from a client balance without allowing overdrafts.
    func redeemPoints(client: Client, points: Int, reason: String? = nil) async throws {
        guard points > 0 else {
            throw AppError.validation(.custom(message: "Loyalty redemption must be greater than zero."))
        }

        guard client.loyaltyPoints >= points else {
            throw AppError.database("Insufficient loyalty points")
        }

        client.loyaltyPoints -= points
        stampClientMutation(client)
        recordLedgerEntry(kind: .redeemed, points: -points, client: client, reason: reason)
        try modelContext.save()
        await recordClientChange(
            operation: "Redeemed loyalty points",
            client: client,
            changedKeys: ["loyaltyPoints", "updatedAt", "lastModifiedBy"]
        )
    }

    /// Applies a staff-entered loyalty balance correction.
    func adjustPoints(client: Client, delta: Int, reason: String? = nil) async throws {
        guard delta != 0 else {
            throw AppError.validation(.custom(message: "Loyalty adjustment must not be zero."))
        }

        let adjustedBalance = client.loyaltyPoints + delta
        guard adjustedBalance >= 0 else {
            throw AppError.database("Loyalty adjustment cannot overdraw the client balance")
        }

        client.loyaltyPoints = adjustedBalance
        stampClientMutation(client)
        recordLedgerEntry(kind: .adjusted, points: delta, client: client, reason: reason)
        try modelContext.save()
        await recordClientChange(
            operation: "Adjusted loyalty points",
            client: client,
            changedKeys: ["loyaltyPoints", "updatedAt", "lastModifiedBy"]
        )
    }

    private func recordLedgerEntry(kind: LoyaltyLedgerEntry.Kind, points: Int, client: Client, reason: String?) {
        let entry = LoyaltyLedgerEntry(
            kind: kind,
            points: points,
            clientUUID: client.uuid,
            balanceAfter: client.loyaltyPoints,
            reason: reason
        )
        modelContext.insert(entry)
    }

    private func stampClientMutation(_ client: Client) {
        client.updatedAt = .now
        client.lastModifiedBy = DeviceIdentity.currentID
    }

    private func recordClientChange(operation: String, client: Client, changedKeys: [String]) async {
        let clientUUID = client.uuid
        await MainActor.run {
            CloudKitMonitor.shared.recordLocalChange(
                operation,
                entityName: "Client",
                recordUUID: clientUUID,
                changedKeys: changedKeys
            )
        }
    }
}
