import XCTest
@testable import Pawtrackr

final class CheckoutDraftStoreTests: XCTestCase {

    func testDraftRoundTrip_SaveLoadDelete() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = CheckoutDraftStore(directoryURL: root)
        let visitID = UUID()
        let petID = UUID()

        let draft = CheckoutDraft(
            visitID: visitID,
            petID: petID,
            currentStepRawValue: 2,
            sessionNotes: "Calm during groom",
            amountString: "$42.00",
            selectedServiceUUIDs: [UUID()],
            selectedAddOnUUIDs: [UUID()],
            selectedPaymentMethodRawValue: Payment.Method.cash.rawValue,
            beforePhotoData: Data([0x01, 0x02]),
            afterPhotoData: Data([0x03, 0x04]),
            externalReference: "1234",
            tags: ["Friendly"]
        )

        try await store.saveDraft(draft)
        let loaded = await store.loadDraft(for: visitID)
        XCTAssertEqual(loaded, draft)

        try await store.deleteDraft(for: visitID)
        let deleted = await store.loadDraft(for: visitID)
        XCTAssertNil(deleted)
    }
}
