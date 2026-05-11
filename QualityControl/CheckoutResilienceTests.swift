import XCTest
import SwiftData
@testable import Pawtrackr

final class CheckoutResilienceTests: XCTestCase {

    @MainActor
    func testCheckoutIdempotency() async throws {
        let dataStore = DataStoreService(inMemory: true)
        let container = dataStore.container
        let actor = CheckoutTransactionActor(modelContainer: container)
        
        // 1. Setup Mock Data
        let pet = Pet(name: "Resilient Pet", species: .dog, gender: .male)
        container.mainContext.insert(pet)
        try container.mainContext.save()
        
        let visitUUID = UUID()
        let request = CheckoutRequest(
            visitUUID: visitUUID,
            petUUID: pet.uuid,
            clientUUID: nil,
            amount: 50.0,
            paymentMethod: .cash,
            externalReference: nil,
            sessionNotes: "Test notes",
            behaviorTags: [],
            beforePhotoData: nil,
            afterPhotoData: nil,
            selectedServiceIDs: [],
            selectedAddOnIDs: []
        )
        
        // 2. First Checkout
        let result1 = try await actor.process(request)
        XCTAssertEqual(result1.total, 50.0)
        
        // 3. Second Checkout (Same Idempotency Key)
        // Should return the same result without creating duplicate payments or visits
        let result2 = try await actor.process(request)
        XCTAssertEqual(result1.visitID, result2.visitID)
        XCTAssertEqual(result1.endedAt, result2.endedAt)
        
        // 4. Verify no duplicates in DB
        let visits = try container.mainContext.fetch(FetchDescriptor<Visit>())
        XCTAssertEqual(visits.count, 1, "Should only have one visit despite multiple checkout attempts")
        
        let payments = try container.mainContext.fetch(FetchDescriptor<Payment>())
        XCTAssertEqual(payments.count, 1, "Should only have one payment record")
    }
    
    @MainActor
    func testCheckoutCrashRecovery() async throws {
        let dataStore = DataStoreService(inMemory: true)
        let container = dataStore.container
        let actor = CheckoutTransactionActor(modelContainer: container)
        
        let pet = Pet(name: "Crash Pet", species: .dog, gender: .male)
        container.mainContext.insert(pet)
        try container.mainContext.save()
        
        let visitUUID = UUID()
        let request = CheckoutRequest(
            visitUUID: visitUUID,
            petUUID: pet.uuid,
            clientUUID: nil,
            amount: 100.0,
            paymentMethod: .creditCard,
            externalReference: "REF123",
            sessionNotes: "Recovery test",
            behaviorTags: [],
            beforePhotoData: nil,
            afterPhotoData: nil,
            selectedServiceIDs: [],
            selectedAddOnIDs: []
        )
        
        // Simulate a partial failure by manually inserting a "processing" transaction
        let transaction = CheckoutTransaction(
            idempotencyKey: "checkout:\(visitUUID.uuidString)",
            visitUUID: visitUUID,
            petUUID: pet.uuid,
            clientUUID: nil,
            amount: 100.0,
            method: .creditCard,
            externalReference: "REF123"
        )
        transaction.status = .processing
        container.mainContext.insert(transaction)
        try container.mainContext.save()
        
        // Now run the actor process - it should pick up the processing transaction and complete it
        let result = try await actor.process(request)
        XCTAssertEqual(result.total, 100.0)
        
        let transactions = try container.mainContext.fetch(FetchDescriptor<CheckoutTransaction>())
        XCTAssertEqual(transactions.first?.status, .succeeded)
    }
}
