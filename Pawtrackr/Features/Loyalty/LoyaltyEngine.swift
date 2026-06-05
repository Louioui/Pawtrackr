import Foundation
import SwiftData

/// Domain engine for loyalty point calculations.
struct LoyaltyEngine {
    /// Calculates points earned based on total spent.
    /// Example: 1 point per $1 spent, rounded down.
    static func calculatePoints(for total: Decimal) -> Int {
        // Banker's rounding for point calculation
        let rounded = total.roundedMoney()
        return (rounded as NSDecimalNumber).intValue
    }
}
