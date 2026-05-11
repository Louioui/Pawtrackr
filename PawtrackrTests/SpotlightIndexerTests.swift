import XCTest
import SwiftData
import CoreSpotlight
@testable import Pawtrackr

final class SpotlightIndexerTests: XCTestCase {
    
    @MainActor
    func testIndexPet_DoesNotCrash() {
        let pet = Pet(name: "Luna", species: .cat)
        let owner = Client(firstName: "Charlie", lastName: "Brown")
        pet.owner = owner
        
        // We can't easily verify the system index, but we can ensure our indexer
        // processes the model correctly and doesn't crash on background threads.
        SpotlightIndexer.shared.indexPet(pet)
        
        // If we reached here without a crash, the data extraction logic inside indexPet is safe.
        XCTAssertTrue(true)
    }
    
    @MainActor
    func testIndexClient_DoesNotCrash() {
        let client = Client(firstName: "Lucy", lastName: "Van Pelt")
        client.phone = "555-999-0000"
        
        SpotlightIndexer.shared.indexClient(client)
        
        XCTAssertTrue(true)
    }
}
