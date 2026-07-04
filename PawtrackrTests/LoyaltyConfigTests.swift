import XCTest
import SwiftData
@testable import Pawtrackr

final class LoyaltyConfigTests: XCTestCase {
    func testDefaultConfigPreservesCurrentBusinessRules() {
        let config = LoyaltyConfig()

        XCTAssertEqual(config.earnMode, .pointsPerDollar)
        XCTAssertEqual(config.pointsPerDollar, Decimal(1))
        XCTAssertEqual(config.pointsPerVisit, 20)
        XCTAssertEqual(config.redemptionThreshold, 100)
        XCTAssertTrue(config.isRewardsCatalogEnabled)
    }

    func testConfigRejectsInvalidValuesByClampingToSafeDefaults() {
        let config = LoyaltyConfig()

        config.setPointsPerDollar(Decimal(string: "-2.5")!)
        config.setPointsPerVisit(-10)
        config.setRedemptionThreshold(0)

        XCTAssertEqual(config.pointsPerDollar, Decimal(0))
        XCTAssertEqual(config.pointsPerVisit, 0)
        XCTAssertEqual(config.redemptionThreshold, 1)
    }

    func testRewardTemplatesSeedFromBuiltInCatalog() {
        let templates = LoyaltyRewardTemplate.seedTemplates()

        XCTAssertEqual(templates.map(\.pointCost), LoyaltyReward.builtInCatalog.map(\.pointCost))
        XCTAssertEqual(templates.first?.title, LoyaltyReward.builtInCatalog.first?.title)
        XCTAssertTrue(templates.allSatisfy(\.isEnabled))
    }

    func testRewardTemplateRequiresPositiveCost() {
        let reward = LoyaltyRewardTemplate(
            title: "Free Nail Trim",
            detail: "A returning-client reward.",
            pointCost: -50,
            systemImage: "scissors",
            styleRaw: LoyaltyReward.Style.care.rawValue,
            sortOrder: 0
        )

        XCTAssertEqual(reward.pointCost, 1)
    }
}
