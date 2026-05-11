import XCTest
import SwiftData
@testable import Pawtrackr

final class CheckoutIdempotencyTests: XCTestCase {
    var container: ModelContainer!

    override func setUpWithError() throws {
        let schema = Schema(PawtrackrSchema.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
    }

    func testCheckoutIdempotency_PreventsDuplicatePayments() async throws {
        let visitUUID = UUID()
        let petUUID = UUID()
        
        // Seed Pet
        let context = ModelContext(container)
        let pet = Pet(name: "Idempotent Pet", species: .dog)
        pet.uuid = petUUID
        context.insert(pet)
        try context.save()
        
        let actor = CheckoutTransactionActor(modelContainer: container)
        
        let request = CheckoutRequest(
            visitUUID: visitUUID,
            petUUID: petUUID,
            clientUUID: nil,
            amount: 100.0,
            paymentMethod: .cash,
            externalReference: nil,
            sessionNotes: "First attempt",
            behaviorTags: [],
            beforePhotoData: nil,
            afterPhotoData: nil,
            selectedServiceIDs: [],
            selectedAddOnIDs: []
        )
        
        // 1. Process first time
        let result1 = try await actor.process(request)
        
        // 2. Process second time (exact same UUIDs)
        let result2 = try await actor.process(request)
        
        // 3. Verify
        let fetchVisits = FetchDescriptor<Visit>(predicate: #Predicate { $0.uuid == visitUUID })
        let visits = try context.fetch(fetchVisits)
        
        XCTAssertEqual(visits.count, 1, "There should only be ONE visit record even after two checkout calls.")
        XCTAssertEqual(result1.endedAt, result2.endedAt, "The second result should return the SAME completion date as the first.")
        
        let fetchPayments = FetchDescriptor<Payment>()
        let payments = try context.fetch(fetchPayments)
        XCTAssertEqual(payments.count, 1, "There should only be ONE payment record recorded.")
    }
    
    func testReconcileLineItemPrices_HandlesRoundingAndDiscounts() async throws {
        let context = ModelContext(container)
        let pet = Pet(name: "Math Pet", species: .dog)
        context.insert(pet)
        
        let service1 = Service(name: "S1", category: .groom, basePrice: 33.33)
        let service2 = Service(name: "S2", category: .groom, basePrice: 33.33)
        let service3 = Service(name: "S3", category: .groom, basePrice: 33.33)
        context.insert(service1)
        context.insert(service2)
        context.insert(service3)
        try context.save()
        
        let actor = CheckoutTransactionActor(modelContainer: container)
        
        // User overrides the $99.99 total to exactly $100.00
        let request = CheckoutRequest(
            visitUUID: UUID(),
            petUUID: pet.uuid,
            clientUUID: nil,
            amount: 100.0,
            paymentMethod: .cash,
            externalReference: nil,
            sessionNotes: nil,
            behaviorTags: [],
            beforePhotoData: nil,
            afterPhotoData: nil,
            selectedServiceIDs: [service1.persistentModelID, service2.persistentModelID, service3.persistentModelID],
            selectedAddOnIDs: []
        )
        
        _ = try await actor.process(request)
        
        // Verify line items sum to exactly 100.00
        let visit = try context.fetch(FetchDescriptor<Visit>()).first!
        let items = visit.items ?? []
        let totalSum = items.reduce(Decimal.zero) { $0 + $1.lineTotal }
        
        XCTAssertEqual(totalSum, 100.00)
        // Last item usually takes the rounding cent
        XCTAssertEqual(items.last?.lineTotal, 33.34)
    }
}
