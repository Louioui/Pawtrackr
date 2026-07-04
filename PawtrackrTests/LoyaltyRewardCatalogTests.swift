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

    func testTemplateDisplayRewardKeepsRedeemabilityRules() {
        let template = LoyaltyRewardTemplate(
            title: "$10 Credit",
            detail: "Apply at checkout.",
            pointCost: 100,
            systemImage: "ticket.fill",
            styleRaw: LoyaltyReward.Style.credit.rawValue,
            sortOrder: 0
        )

        let reward = template.displayReward

        XCTAssertFalse(reward.isRedeemable(with: 99))
        XCTAssertTrue(reward.isRedeemable(with: 100))
    }
}
