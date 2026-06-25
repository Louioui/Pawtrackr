import Foundation
import SwiftData

@ModelActor
actor LoyaltyService {
    
    func applyPoints(for visit: Visit) throws {
        guard let client = visit.pet?.owner else { return }
        
        let points = LoyaltyEngine.calculatePoints(for: visit.total)
        
        // Update client
        client.loyaltyPoints += points
        
        // Update visit history
        visit.loyaltyPointsChange = points
        
        try modelContext.save()
    }
    
    func redeemPoints(client: Client, points: Int) throws {
        guard points > 0 else {
            throw AppError.validation(.custom(message: "Loyalty redemption must be greater than zero."))
        }

        guard client.loyaltyPoints >= points else {
            throw AppError.database("Insufficient loyalty points")
        }
        
        client.loyaltyPoints -= points
        try modelContext.save()
    }
}
