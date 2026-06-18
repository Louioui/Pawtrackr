import XCTest
import SwiftData
@testable import Pawtrackr

@MainActor
final class BehaviorSafetyAlgorithmTests: XCTestCase {
    private var container: ModelContainer!
    private var petUUID: UUID!

    override func setUp() async throws {
        try await super.setUp()
        let schema = Schema(PawtrackrSchema.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [config])

        let store = BehaviorSafetyTestStore(modelContainer: container)
        petUUID = try await store.seedAggressivePet()
    }

    override func tearDown() async throws {
        petUUID = nil
        container = nil
        try await super.tearDown()
    }

    func testAggressivePetKeepsSafetyFlagUntilThreeConsecutiveCalmOrCooperativeVisits() async throws {
        try await completeCheckout(with: ["Calm"])
        let firstVisitPet = try await petSnapshot()
        XCTAssertTrue(firstVisitPet.isAggressive, "One calm visit must not clear the staff safety warning.")

        try await completeCheckout(with: ["Cooperative"])
        let secondVisitPet = try await petSnapshot()
        XCTAssertTrue(secondVisitPet.isAggressive, "Two calm/cooperative visits must not clear the staff safety warning.")

        try await completeCheckout(with: ["Calm", "Cooperative"])

        let updatedPet = try await petSnapshot()
        XCTAssertFalse(updatedPet.isAggressive, "Three consecutive calm/cooperative visits should retire the aggressive warning.")
        XCTAssertEqual(Set(updatedPet.behaviorTags), Set(["Calm", "Cooperative"]))
    }

    func testAggressiveIncidentResetsCalmStreakAndRequiresThreeNewClearVisits() async throws {
        try await completeCheckout(with: ["Calm"])
        try await completeCheckout(with: ["Cooperative"])
        try await completeCheckout(with: ["Aggressive"])
        let incidentPet = try await petSnapshot()
        XCTAssertTrue(incidentPet.isAggressive, "An aggressive third visit must keep the safety warning active.")

        try await completeCheckout(with: ["Calm"])
        try await completeCheckout(with: ["Cooperative"])
        let restartedStreakPet = try await petSnapshot()
        XCTAssertTrue(restartedStreakPet.isAggressive, "The streak must restart after an aggressive incident.")

        try await completeCheckout(with: ["Calm"])
        let clearedPet = try await petSnapshot()
        XCTAssertFalse(clearedPet.isAggressive, "Three new calm/cooperative visits after the reset should clear the warning.")
    }

    func testSpanishCalmAndCooperativeTagsCanClearAggressiveWarning() async throws {
        try await completeCheckout(with: ["Tranquilo"])
        try await completeCheckout(with: ["Cooperativo"])
        try await completeCheckout(with: ["Tranquilo", "Cooperativo"])

        let updatedPet = try await petSnapshot()
        XCTAssertFalse(updatedPet.isAggressive)
        XCTAssertEqual(Set(updatedPet.behaviorTags), Set(["Tranquilo", "Cooperativo"]))
    }

    private func completeCheckout(with behaviorTags: [String]) async throws {
        let actor = CheckoutTransactionActor(modelContainer: container)
        let request = CheckoutRequest(
            visitUUID: UUID(),
            petUUID: petUUID,
            clientUUID: nil,
            amount: Decimal(40),
            paymentMethod: .cash,
            externalReference: nil,
            sessionNotes: nil,
            behaviorTags: behaviorTags,
            beforePhotoData: nil,
            afterPhotoData: nil,
            selectedServiceIDs: [],
            selectedAddOnIDs: []
        )

        _ = try await actor.process(request)
        try await Task.sleep(for: .milliseconds(5))
    }

    private func petSnapshot() async throws -> BehaviorSafetyPetSnapshot {
        let store = BehaviorSafetyTestStore(modelContainer: container)
        return try await store.snapshot(for: petUUID)
    }
}

private struct BehaviorSafetyPetSnapshot: Sendable {
    let behaviorTags: [String]
    let isAggressive: Bool
}

@ModelActor
private actor BehaviorSafetyTestStore {
    func seedAggressivePet() throws -> UUID {
        let pet = Pet(name: "Safety Buddy", species: .dog)
        pet.setBehaviorTags(["Aggressive"])
        modelContext.insert(pet)
        try modelContext.save()
        return pet.uuid
    }

    func snapshot(for petUUID: UUID) throws -> BehaviorSafetyPetSnapshot {
        var descriptor = FetchDescriptor<Pet>(predicate: #Predicate<Pet> { $0.uuid == petUUID })
        descriptor.fetchLimit = 1
        let pet = try XCTUnwrap(try modelContext.fetch(descriptor).first)
        return BehaviorSafetyPetSnapshot(
            behaviorTags: pet.behaviorTags,
            isAggressive: pet.isAggressive
        )
    }
}
