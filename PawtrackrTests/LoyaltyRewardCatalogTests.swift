import XCTest
@testable import Pawtrackr

final class LoyaltyRewardCatalogTests: XCTestCase {
    func testBuiltInCatalogOrdersRewardsByPointCost() {
        let costs = LoyaltyReward.builtInCatalog.map(\.pointCost)

        XCTAssertEqual(costs, costs.sorted())
    }

    func testRewardEligibilityRequiresEnoughPoints() throws {
        let reward = try XCTUnwrap(LoyaltyReward.builtInCatalog.first)

        XCTAssertFalse(reward.isRedeemable(with: reward.pointCost - 1))
        XCTAssertTrue(reward.isRedeemable(with: reward.pointCost))
    }
}
