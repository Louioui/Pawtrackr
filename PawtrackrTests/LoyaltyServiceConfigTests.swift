import XCTest
import SwiftData
@testable import Pawtrackr

@MainActor
final class LoyaltyServiceConfigTests: XCTestCase {
    var container: ModelContainer!

    override func setUpWithError() throws {
        let schema = Schema(PawtrackrSchema.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(
            for: schema,
            migrationPlan: PawtrackrMigrationPlan.self,
            configurations: [config]
        )
        DataMigrations.ensureLoyaltyDefaults(in: container.mainContext)
    }

    override func tearDownWithError() throws {
        container = nil
    }

    func testUpdateConfigPersistsFlatVisitMode() async throws {
        let service = LoyaltyService(modelContainer: container)

        try await service.updateConfig(
            earnMode: .flatPerVisit,
            pointsPerDollar: Decimal(1),
            pointsPerVisit: 20,
            redemptionThreshold: 100,
            isRewardsCatalogEnabled: true
        )

        let context = ModelContext(container)
        let config = try XCTUnwrap(try context.fetch(FetchDescriptor<LoyaltyConfig>()).first)
        XCTAssertEqual(config.earnMode, .flatPerVisit)
        XCTAssertEqual(config.pointsPerVisit, 20)
        XCTAssertEqual(config.redemptionThreshold, 100)
    }

    func testUpdateConfigMergesOnlyProvidedFields() async throws {
        let service = LoyaltyService(modelContainer: container)

        try await service.updateConfig(
            earnMode: .flatPerVisit,
            pointsPerDollar: Decimal(4),
            pointsPerVisit: 45,
            redemptionThreshold: 250,
            isRewardsCatalogEnabled: false
        )
        try await service.updateConfig(pointsPerVisit: 70)

        let context = ModelContext(container)
        let config = try XCTUnwrap(try context.fetch(FetchDescriptor<LoyaltyConfig>()).first)
        XCTAssertEqual(config.earnMode, .flatPerVisit)
        XCTAssertEqual(config.pointsPerDollar, Decimal(4))
        XCTAssertEqual(config.pointsPerVisit, 70)
        XCTAssertEqual(config.redemptionThreshold, 250)
        XCTAssertFalse(config.isRewardsCatalogEnabled)
    }

    func testCreateRewardTemplatePersistsReward() async throws {
        let service = LoyaltyService(modelContainer: container)

        try await service.createRewardTemplate(
            title: "Free Nail Trim",
            detail: "Redeem after five visits.",
            pointCost: 100,
            systemImage: "scissors",
            style: .care
        )

        let context = ModelContext(container)
        let rewards = try context.fetch(FetchDescriptor<LoyaltyRewardTemplate>())
        XCTAssertTrue(rewards.contains { $0.title == "Free Nail Trim" && $0.pointCost == 100 })
    }

    func testCreateRewardTemplateRejectsInvalidCost() async throws {
        let service = LoyaltyService(modelContainer: container)

        do {
            try await service.createRewardTemplate(
                title: "Bad Reward",
                detail: "Invalid",
                pointCost: 0,
                systemImage: "gift.fill",
                style: .credit
            )
            XCTFail("Zero-cost rewards must be rejected.")
        } catch let error as AppError {
            guard case .validation = error else {
                return XCTFail("Expected validation error, got \(error).")
            }
        }
    }
}
