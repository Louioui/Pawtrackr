import XCTest
@testable import Pawtrackr

@MainActor
final class ClientCardVisualStateTests: XCTestCase {
    func testClearingAggressiveBehaviorDropsSafetyAccentAndChangesCardIdentity() {
        let client = Client(firstName: "Hello", lastName: "World", phone: "3157818455")
        let pet = Pet(name: "Why", species: .dog)
        pet.setBehaviorTags(["Aggressive"])
        client.addPet(pet)

        let aggressiveState = ClientCard.VisualState(client: client, isInProgressOverride: false)
        XCTAssertTrue(aggressiveState.showsAggressiveWarning)
        XCTAssertEqual(aggressiveState.accentKind, .safety)

        pet.setBehaviorTags(["Calm", "Cooperative"])

        let clearedState = ClientCard.VisualState(client: client, isInProgressOverride: false)
        XCTAssertFalse(clearedState.showsAggressiveWarning)
        XCTAssertNil(clearedState.accentKind)
        XCTAssertNotEqual(
            aggressiveState.identityKey,
            clearedState.identityKey,
            "The card identity must change when the safety rail is removed so iOS/iPad LazyVStack reuse cannot leave the old red overlay behind."
        )
    }

    func testInProgressAccentDoesNotBecomeSafetyAccentWhenPetIsNotAggressive() {
        let client = Client(firstName: "Luis", lastName: "Pacheco")
        let pet = Pet(name: "Loui", species: .dog)
        pet.setBehaviorTags(["Cooperative"])
        client.addPet(pet)

        let state = ClientCard.VisualState(client: client, isInProgressOverride: true)

        XCTAssertFalse(state.showsAggressiveWarning)
        XCTAssertEqual(state.accentKind, .inProgress)
    }
}
