import XCTest
import SwiftData
import CoreSpotlight
@testable import Pawtrackr

final class SpotlightIndexerTests: XCTestCase {
    
    @MainActor
    func testPetSnapshot_CarriesOwnerNameAndPhoneAndThumbnailOnly() {
        let owner = Client(firstName: "Charlie", lastName: "Brown", phone: "+15559990000")
        let pet = Pet(name: "Luna", species: .cat)
        pet.owner = owner
        pet.photoData = Data([1, 2, 3])
        pet.thumbnailData = nil

        let snapshot = SpotlightPetSnapshot(pet: pet)

        XCTAssertEqual(snapshot.id, pet.uuid)
        XCTAssertEqual(snapshot.name, "Luna")
        XCTAssertEqual(snapshot.species, .cat)
        XCTAssertEqual(snapshot.ownerFirstName, "Charlie")
        XCTAssertEqual(snapshot.ownerLastName, "Brown")
        XCTAssertEqual(snapshot.ownerPhone, "+15559990000")
        XCTAssertNil(snapshot.thumbnailData, "The full photo must never be handed to Spotlight.")
    }

    @MainActor
    func testClientSnapshot_CarriesPhoneEmailAndPetNames() {
        let client = Client(firstName: "Lucy", lastName: "Van Pelt", phone: "555-999-0000", email: "Lucy@Example.com")
        let pet = Pet(name: "Snoopy", species: .dog)
        client.pets = [pet]

        let snapshot = SpotlightClientSnapshot(client: client)

        XCTAssertEqual(snapshot.id, client.uuid)
        XCTAssertEqual(snapshot.firstName, "Lucy")
        XCTAssertEqual(snapshot.lastName, "Van Pelt")
        XCTAssertEqual(snapshot.phone, "555-999-0000")
        XCTAssertEqual(snapshot.email, "lucy@example.com")
        XCTAssertEqual(snapshot.petNames, ["Snoopy"])
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
