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
        } catch {
            // Expected: invalid redemption amounts are rejected before mutation.
        }

        XCTAssertEqual(client.loyaltyPoints, 20)
    }
}
