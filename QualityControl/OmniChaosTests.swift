import XCTest
import SwiftData
@testable import Pawtrackr

final class OmniChaosTests: XCTestCase {

    @MainActor
    func testEndToEndWorkflowRaceConditions() async throws {
        let dataStore = DataStoreService(inMemory: true)
        let container = dataStore.container
        let eventBus = GlobalEventBus()
        
        let clientRepo = ClientRepository(modelContainer: container)
        let visitRepo = VisitRepository(modelContainer: container, eventBus: eventBus)
        
        // Chaos simulation: Rapidly create and check out pets across multiple tasks
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    // 1. Create Client
                    let client = Client(firstName: "Chaos", lastName: "\(i)")
                    try? await clientRepo.saveClient(client)
                    
                    // 2. Add Pet
                    let pet = Pet(name: "Pet \(i)", species: .dog, gender: .male)
                    client.addPet(pet)
                    
                    // 3. Check In
                    let visit = try? await visitRepo.checkIn(pet: pet, date: .now)
                    
                    // 4. Heavy Analytics request while saving
                    let insights = InsightsActor(modelContainer: container)
                    _ = try? await insights.fetchRevenue(periodDays: 7)
                    
                    // 5. Check Out
                    if let visit = visit {
                        let actor = CheckoutTransactionActor(modelContainer: container)
                        let request = CheckoutRequest(
                            visitUUID: visit.uuid,
                            petUUID: pet.uuid,
                            clientUUID: client.uuid,
                            amount: 100.0,
                            paymentMethod: .cash,
                            externalReference: nil,
                            sessionNotes: nil,
                            behaviorTags: [],
                            beforePhotoData: nil,
                            afterPhotoData: nil,
                            selectedServiceIDs: [],
                            selectedAddOnIDs: []
                        )
                        _ = try? await actor.process(request)
                    }
                }
            }
        }
        
        // Verification
        let visits = try container.mainContext.fetch(FetchDescriptor<Visit>())
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
