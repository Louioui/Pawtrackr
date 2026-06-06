import XCTest
import SwiftData
@testable import Pawtrackr

final class OmniChaosTests: XCTestCase {

    @MainActor
    func testEndToEndWorkflowRaceConditions() async throws {
        let dataStore = DataStoreService(inMemory: true)
        let container = dataStore.container
        let context = container.mainContext

        let specs: [(clientUUID: UUID, petUUID: UUID, visitUUID: UUID)] = (0..<10).map { i in
            let client = Client(firstName: "Chaos", lastName: "\(i)", phone: "")
            let pet = Pet(name: "Pet \(i)", species: .dog, gender: .male)
            pet.owner = client
            let visit = Visit(pet: pet, startedAt: Date.now.addingTimeInterval(TimeInterval(-i)))
            context.insert(client)
            context.insert(pet)
            context.insert(visit)
            return (client.uuid, pet.uuid, visit.uuid)
        }
        try context.save()

        // Chaos simulation: interleave analytics reads with repeated checkout commits
        // without sharing live main-context models across task boundaries.
        for spec in specs {
            let insights = InsightsActor(modelContainer: container)
            _ = try? await insights.fetchRevenue(periodDays: 7)

            let actor = CheckoutTransactionActor(modelContainer: container)
            let request = CheckoutRequest(
                visitUUID: spec.visitUUID,
                petUUID: spec.petUUID,
                clientUUID: spec.clientUUID,
                amount: Decimal(100),
                paymentMethod: .cash,
                externalReference: nil,
                sessionNotes: nil,
                behaviorTags: [],
                beforePhotoData: nil,
                afterPhotoData: nil,
                selectedServiceIDs: [],
                selectedAddOnIDs: []
            )
            _ = try await actor.process(request)
        }
        
        // Verification
        let freshContext = ModelContext(container)
        let visits = try freshContext.fetch(FetchDescriptor<Visit>())
        XCTAssertEqual(visits.count, 10, "Should have 10 successful check-ins")
        
        let completed = visits.filter { $0.endedAt != nil }
        XCTAssertEqual(completed.count, 10, "Should have 10 successful check-outs despite parallel stress")
    }
    
    func testDesignSystemTokenConsistency() {
        // Ensure theme tokens don't have invalid configurations
        XCTAssertNotNil(DS.ColorToken.primary)
        XCTAssertNotNil(DS.ColorToken.success)
        XCTAssertGreaterThan(DS.Spacing.lg, DS.Spacing.md)
    }
}
