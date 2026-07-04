import XCTest
import SwiftData
@testable import Pawtrackr

final class LoyaltyServiceTests: XCTestCase {
    var container: ModelContainer!

    override func setUpWithError() throws {
        let schema = Schema(PawtrackrSchema.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
    }

    func testCalculatePoints_DoesNotMintNegativePoints() {
        XCTAssertEqual(LoyaltyEngine.calculatePoints(for: Decimal(string: "-12.34")!), 0)
    }

    func testRedeemPoints_RejectsNegativeRedemptionWithoutMutatingBalance() async throws {
        let client = Client(firstName: "Ava", lastName: "Martinez")
        client.loyaltyPoints = 20
        let service = LoyaltyService(modelContainer: container)

        do {
            try await service.redeemPoints(client: client, points: -5)
            XCTFail("Negative redemptions must not be accepted.")
        } catch let error as AppError {
            // Expected: invalid redemption amounts are rejected before mutation.
            guard case .validation = error else {
                return XCTFail("Expected a validation error, got \(error).")
            }
        }
        // Any non-AppError throw propagates out of this `throws` test and fails it,
        // so unrelated runtime/infrastructure failures no longer pass silently.

        XCTAssertEqual(client.loyaltyPoints, 20)
    }

    func testRedeemPoints_StampsClientMutationForSync() async throws {
        let client = Client(firstName: "Maya", lastName: "Chen")
        client.loyaltyPoints = 150
        let originalUpdatedAt = client.updatedAt
        let service = LoyaltyService(modelContainer: container)

        try await service.redeemPoints(client: client, points: 50)

        XCTAssertEqual(client.loyaltyPoints, 100)
        XCTAssertGreaterThan(client.updatedAt, originalUpdatedAt)
        XCTAssertEqual(client.lastModifiedBy, DeviceIdentity.currentID)
    }

    func testAdjustPoints_AddsPositiveAdjustmentAndStampsClient() async throws {
        let client = Client(firstName: "Rosa", lastName: "Nguyen")
        client.loyaltyPoints = 15
        let originalUpdatedAt = client.updatedAt
        let service = LoyaltyService(modelContainer: container)

        try await service.adjustPoints(client: client, delta: 25)

        XCTAssertEqual(client.loyaltyPoints, 40)
        XCTAssertGreaterThan(client.updatedAt, originalUpdatedAt)
    }

    func testAdjustPoints_RejectsAdjustmentThatWouldOverdrawBalance() async throws {
        let client = Client(firstName: "Theo", lastName: "Brooks")
        client.loyaltyPoints = 10
        let service = LoyaltyService(modelContainer: container)

        do {
            try await service.adjustPoints(client: client, delta: -25)
            XCTFail("Manual adjustments must not leave a client with negative loyalty points.")
        } catch let error as AppError {
            guard case .database = error else {
                return XCTFail("Expected a database error, got \(error).")
            }
        }

        XCTAssertEqual(client.loyaltyPoints, 10)
    }

    func testAdjustPoints_RejectsZeroAdjustment() async throws {
        let client = Client(firstName: "Nina", lastName: "Patel")
        client.loyaltyPoints = 10
        let service = LoyaltyService(modelContainer: container)

        do {
            try await service.adjustPoints(client: client, delta: 0)
            XCTFail("A zero-point adjustment should not be persisted.")
        } catch let error as AppError {
            guard case .validation = error else {
                return XCTFail("Expected a validation error, got \(error).")
            }
        }

        XCTAssertEqual(client.loyaltyPoints, 10)
    }
}
