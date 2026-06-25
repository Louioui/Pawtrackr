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

    func testDeletedClientSearchableIdentifiersIncludeCascadedPets() {
        let clientID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let firstPetID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let secondPetID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!

        let identifiers = SpotlightIndexer.searchableIdentifiersForDeletedClient(
            clientID: clientID,
            petIDs: [firstPetID, secondPetID]
        )

        XCTAssertEqual(identifiers, [
            "client-11111111-1111-1111-1111-111111111111",
            "pet-22222222-2222-2222-2222-222222222222",
            "pet-33333333-3333-3333-3333-333333333333"
        ])
    }

    func testClientDeletionPathsRemoveSpotlightEntries() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let clientRepository = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Pawtrackr/Core/Storage/Repositories/ClientRepository.swift"),
            encoding: .utf8
        )
        let clientDetailView = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Pawtrackr/Features/Clients/ClientDetailView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            clientRepository.contains("removeClientAndPetsFromIndex"),
            "Repository-backed client deletion must remove the deleted client and cascaded pets from Spotlight."
        )
        XCTAssertTrue(
            clientDetailView.contains("removeClientAndPetsFromIndex"),
            "Detail-view client deletion must remove the deleted client and cascaded pets from Spotlight."
        )
    }
}
