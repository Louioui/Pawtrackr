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

    // MARK: - Ledger audit trail

    func testRedeemPoints_WritesRedemptionLedgerEntry() async throws {
        let client = Client(firstName: "Iris", lastName: "Kwon")
        client.loyaltyPoints = 150
        let service = LoyaltyService(modelContainer: container)

        try await service.redeemPoints(client: client, points: 100, reason: "$10 Salon Credit")

        let entries = try fetchLedgerEntries()
        XCTAssertEqual(entries.count, 1)
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry.kind, .redeemed)
        XCTAssertEqual(entry.points, -100)
        XCTAssertEqual(entry.balanceAfter, 50)
        XCTAssertEqual(entry.reason, "$10 Salon Credit")
        XCTAssertEqual(entry.clientUUID, client.uuid)
    }

    func testAdjustPoints_WritesAdjustmentLedgerEntry() async throws {
        let client = Client(firstName: "Omar", lastName: "Reyes")
        client.loyaltyPoints = 15
        let service = LoyaltyService(modelContainer: container)

        try await service.adjustPoints(client: client, delta: 25)

        let entries = try fetchLedgerEntries()
        XCTAssertEqual(entries.count, 1)
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry.kind, .adjusted)
        XCTAssertEqual(entry.points, 25)
        XCTAssertEqual(entry.balanceAfter, 40)
    }

    func testFailedRedemption_WritesNoLedgerEntry() async throws {
        let client = Client(firstName: "Lena", lastName: "Voss")
        client.loyaltyPoints = 10
        let service = LoyaltyService(modelContainer: container)

        do {
            try await service.redeemPoints(client: client, points: 500)
            XCTFail("Overdraft redemption must be rejected.")
        } catch { /* expected */ }

        XCTAssertTrue(try fetchLedgerEntries().isEmpty,
            "A rejected redemption must not leave an audit row behind.")
    }

    // MARK: - Ledger backfill migration

    @MainActor
    func testBackfillLoyaltyLedger_CreatesEntriesOnceForLegacyVisits() throws {
        let context = container.mainContext
        let client = Client(firstName: "Faye", lastName: "Osei")
        context.insert(client)
        let pet = Pet(name: "Mochi", species: .cat)
        pet.owner = client
        context.insert(pet)
        let visit = Visit(pet: pet)
        context.insert(visit)
        visit.loyaltyPointsChange = 85
        visit.setEndedAt(Date(timeIntervalSinceNow: -86_400))
        try context.save()

        DataMigrations.backfillLoyaltyLedger(in: context)
        DataMigrations.backfillLoyaltyLedger(in: context)

        let entries = try fetchLedgerEntries()
        XCTAssertEqual(entries.count, 1, "Backfill must be idempotent across repeated launches.")
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry.kind, .earned)
        XCTAssertEqual(entry.points, 85)
        XCTAssertEqual(entry.visitUUID, visit.uuid)
        XCTAssertEqual(entry.clientUUID, client.uuid)
        XCTAssertNil(entry.balanceAfter, "Historical balances are unknowable; backfilled rows must not invent one.")
    }

    @MainActor
    func testBackfillLoyaltyLedger_CollapsesCrossDeviceDuplicates() throws {
        let context = container.mainContext
        let clientUUID = UUID()
        let visitUUID = UUID()
        let older = LoyaltyLedgerEntry(
            kind: .earned, points: 40, clientUUID: clientUUID, visitUUID: visitUUID,
            createdAt: Date(timeIntervalSinceNow: -7_200)
        )
        let newer = LoyaltyLedgerEntry(
            kind: .earned, points: 40, clientUUID: clientUUID, visitUUID: visitUUID,
            createdAt: Date(timeIntervalSinceNow: -3_600)
        )
        context.insert(older)
        context.insert(newer)
        try context.save()

        DataMigrations.backfillLoyaltyLedger(in: context)

        let entries = try fetchLedgerEntries()
        XCTAssertEqual(entries.count, 1, "Two devices' backfills merged by CloudKit must collapse to one row.")
        XCTAssertEqual(entries.first?.uuid, older.uuid, "Dedupe keeps the earliest-created entry.")
    }

    private func fetchLedgerEntries() throws -> [LoyaltyLedgerEntry] {
        let context = ModelContext(container)
        return try context.fetch(FetchDescriptor<LoyaltyLedgerEntry>())
    }
}
