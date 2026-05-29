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
                group.addTask { @MainActor in
                    // 1. Create Client
                    guard let clientID = try? await clientRepo.createClient(
                        firstName: "Chaos",
                        lastName: "\(i)",
                        phone: "",
                        email: "",
                        address: "",
                        photoData: nil,
                        pets: [
                            NewPetData(
                                name: "Pet \(i)",
                                species: .dog,
                                gender: .male,
                                breed: nil,
                                color: nil,
                                photoData: nil,
                                health: nil,
                                behaviorTags: [],
                                birthdate: nil
                            )
                        ],
                        contacts: []
                    ) else {
                        return
                    }

                    // 2. Resolve the pet in the UI/main context, then check in
                    guard let client = container.mainContext.model(for: clientID) as? Client,
                          let pet = client.pets?.first,
                          let visit = try? await visitRepo.checkIn(pet: pet, date: .now) else {
                        return
                    }
                    let clientUUID = client.uuid
                    let petUUID = pet.uuid
                    let visitUUID = visit.uuid
                    
                    // 4. Heavy Analytics request while saving
                    let insights = InsightsActor(modelContainer: container)
                    _ = try? await insights.fetchRevenue(periodDays: 7)
                    
                    // 5. Check Out
                    let actor = CheckoutTransactionActor(modelContainer: container)
                    let request = CheckoutRequest(
                        visitUUID: visitUUID,
                        petUUID: petUUID,
                        clientUUID: clientUUID,
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
                    _ = try? await actor.process(request)
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
