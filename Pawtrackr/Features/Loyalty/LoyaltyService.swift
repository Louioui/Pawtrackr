import Foundation
import SwiftData

@ModelActor
actor LoyaltyService {

    /// Applies checkout-earned loyalty points to the visit's owning client.
    func applyPoints(for visit: Visit) async throws {
        guard let client = visit.pet?.owner else { return }
        
        let points = LoyaltyEngine.calculatePoints(for: visit.total)
        
        client.loyaltyPoints += points
        stampClientMutation(client)
        
        visit.loyaltyPointsChange = points
        stampVisitMutation(visit)
        
        try modelContext.save()
        await recordClientChange(
            operation: "Applied loyalty points",
            client: client,
            changedKeys: ["loyaltyPoints", "updatedAt", "lastModifiedBy"]
        )
    }

    /// Redeems points from a client balance without allowing overdrafts.
    func redeemPoints(client: Client, points: Int) async throws {
        guard points > 0 else {
            throw AppError.validation(.custom(message: "Loyalty redemption must be greater than zero."))
        }

        guard client.loyaltyPoints >= points else {
            throw AppError.database("Insufficient loyalty points")
        }
        
        client.loyaltyPoints -= points
        stampClientMutation(client)
        try modelContext.save()
        await recordClientChange(
            operation: "Redeemed loyalty points",
            client: client,
            changedKeys: ["loyaltyPoints", "updatedAt", "lastModifiedBy"]
        )
    }

    /// Applies a staff-entered loyalty balance correction.
    func adjustPoints(client: Client, delta: Int) async throws {
        guard delta != 0 else {
            throw AppError.validation(.custom(message: "Loyalty adjustment must not be zero."))
        }

        let adjustedBalance = client.loyaltyPoints + delta
        guard adjustedBalance >= 0 else {
            throw AppError.database("Loyalty adjustment cannot overdraw the client balance")
        }

        client.loyaltyPoints = adjustedBalance
        stampClientMutation(client)
        try modelContext.save()
        await recordClientChange(
            operation: "Adjusted loyalty points",
            client: client,
            changedKeys: ["loyaltyPoints", "updatedAt", "lastModifiedBy"]
        )
    }

    private func stampClientMutation(_ client: Client) {
        client.updatedAt = .now
        client.lastModifiedBy = DeviceIdentity.currentID
    }

    private func stampVisitMutation(_ visit: Visit) {
        visit.updatedAt = .now
        visit.lastModifiedAt = .now
        visit.lastModifiedBy = DeviceIdentity.currentID
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
