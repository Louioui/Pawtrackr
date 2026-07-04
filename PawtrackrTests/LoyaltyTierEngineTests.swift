import XCTest
@testable import Pawtrackr

/// Pure-domain tests for the loyalty tier ladder, earn multipliers, and the
/// rebook bonus. Everything here is integer-deterministic by design — any
/// device must compute the identical award for the same inputs.
final class LoyaltyTierEngineTests: XCTestCase {

    // MARK: - Tier thresholds

    func testTierThresholdBoundaries() {
        XCTAssertEqual(LoyaltyEngine.tier(forLifetimeEarned: 0), .bronze)
        XCTAssertEqual(LoyaltyEngine.tier(forLifetimeEarned: 499), .bronze)
        XCTAssertEqual(LoyaltyEngine.tier(forLifetimeEarned: 500), .silver)
        XCTAssertEqual(LoyaltyEngine.tier(forLifetimeEarned: 1_499), .silver)
        XCTAssertEqual(LoyaltyEngine.tier(forLifetimeEarned: 1_500), .gold)
        XCTAssertEqual(LoyaltyEngine.tier(forLifetimeEarned: 3_499), .gold)
        XCTAssertEqual(LoyaltyEngine.tier(forLifetimeEarned: 3_500), .platinum)
        XCTAssertEqual(LoyaltyEngine.tier(forLifetimeEarned: 1_000_000), .platinum)
    }

    func testNegativeLifetimeEarnedClampsToBronze() {
        XCTAssertEqual(LoyaltyEngine.tier(forLifetimeEarned: -50), .bronze)
    }

    // MARK: - Earn multipliers (integer math, floors — never mints fractions)

    func testEarnedPointsAppliesTierMultiplier() {
        XCTAssertEqual(LoyaltyEngine.earnedPoints(base: 85, tier: .bronze), 85)
        XCTAssertEqual(LoyaltyEngine.earnedPoints(base: 85, tier: .silver), 93)   // 93.5 floors
        XCTAssertEqual(LoyaltyEngine.earnedPoints(base: 85, tier: .gold), 106)    // 106.25 floors
        XCTAssertEqual(LoyaltyEngine.earnedPoints(base: 85, tier: .platinum), 127) // 127.5 floors
    }

    func testEarnedPointsNeverNegativeOrFromZeroBase() {
        for tier in LoyaltyTier.allCases {
            XCTAssertEqual(LoyaltyEngine.earnedPoints(base: 0, tier: tier), 0)
            XCTAssertEqual(LoyaltyEngine.earnedPoints(base: -10, tier: tier), 0)
        }
    }

    func testEarnRateTextFormatting() {
        XCTAssertEqual(LoyaltyTier.bronze.earnRateText, "1×")
        XCTAssertEqual(LoyaltyTier.silver.earnRateText, "1.1×")
        XCTAssertEqual(LoyaltyTier.gold.earnRateText, "1.25×")
        XCTAssertEqual(LoyaltyTier.platinum.earnRateText, "1.5×")
    }

    // MARK: - Tier progress

    func testTierProgressWithinBronze() {
        XCTAssertEqual(LoyaltyEngine.tierProgress(lifetimeEarned: 0), 0)
        XCTAssertEqual(LoyaltyEngine.tierProgress(lifetimeEarned: 250), 0.5)
    }

    func testTierProgressResetsAtEachThresholdAndCapsAtTop() {
        XCTAssertEqual(LoyaltyEngine.tierProgress(lifetimeEarned: 500), 0)
        XCTAssertEqual(LoyaltyEngine.tierProgress(lifetimeEarned: 1_000), 0.5)
        XCTAssertEqual(LoyaltyEngine.tierProgress(lifetimeEarned: 3_500), 1)
        XCTAssertEqual(LoyaltyEngine.tierProgress(lifetimeEarned: 99_999), 1)
    }

    func testPointsUntilNextTier() {
        XCTAssertEqual(LoyaltyEngine.pointsUntilNextTier(lifetimeEarned: 0), 500)
        XCTAssertEqual(LoyaltyEngine.pointsUntilNextTier(lifetimeEarned: 480), 20)
        XCTAssertEqual(LoyaltyEngine.pointsUntilNextTier(lifetimeEarned: 500), 1_000)
        XCTAssertNil(LoyaltyEngine.pointsUntilNextTier(lifetimeEarned: 3_500))
    }

    // MARK: - Rebook bonus

    func testRebookBonusInsideWindow() {
        let now = Date()
        let tenDaysAgo = now.addingTimeInterval(-10 * 86_400)
        XCTAssertEqual(
            LoyaltyEngine.rebookBonus(previousVisitEndedAt: tenDaysAgo, checkoutAt: now, basePoints: 85),
            LoyaltyEngine.rebookBonusPoints
        )
    }

    func testRebookBonusAtExactWindowBoundary() {
        let now = Date()
        let boundary = now.addingTimeInterval(-Double(LoyaltyEngine.rebookWindowDays) * 86_400)
        XCTAssertEqual(
            LoyaltyEngine.rebookBonus(previousVisitEndedAt: boundary, checkoutAt: now, basePoints: 1),
            LoyaltyEngine.rebookBonusPoints
        )
    }

    func testRebookBonusOutsideWindowIsZero() {
        let now = Date()
        let fortySixDaysAgo = now.addingTimeInterval(-46 * 86_400)
        XCTAssertEqual(LoyaltyEngine.rebookBonus(previousVisitEndedAt: fortySixDaysAgo, checkoutAt: now, basePoints: 85), 0)
    }

    func testRebookBonusRequiresPreviousVisitAndEarnedBase() {
        let now = Date()
        XCTAssertEqual(LoyaltyEngine.rebookBonus(previousVisitEndedAt: nil, checkoutAt: now, basePoints: 85), 0)
        let recent = now.addingTimeInterval(-86_400)
        XCTAssertEqual(LoyaltyEngine.rebookBonus(previousVisitEndedAt: recent, checkoutAt: now, basePoints: 0), 0,
            "A $0 visit must not mint a rebook bonus.")
    }

    func testRebookBonusIgnoresFutureTimestampsFromClockSkew() {
        let now = Date()
        let future = now.addingTimeInterval(3_600)
        XCTAssertEqual(LoyaltyEngine.rebookBonus(previousVisitEndedAt: future, checkoutAt: now, basePoints: 85), 0)
    }
}
