import XCTest
import SwiftData
@testable import Pawtrackr

final class StoreHealthCheckTests: XCTestCase {
    var container: ModelContainer!
    
    override func setUpWithError() throws {
        let schema = Schema(PawtrackrSchema.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [config])
    }

    func testIsStoreHealthy_ReturnsTrueForValidContainer() {
        let healthy = StoreHealthCheck.isStoreHealthy(container: container)
        XCTAssertTrue(healthy)
    }
    
    @MainActor
    func testClearAuxiliaryCaches_RebuildsSpotlightFromTheStore() async throws {
        let context = container.mainContext
        let client = Client(firstName: "Ava", lastName: "Martinez", phone: "+15551234567")
        let pet = Pet(name: "Milo", species: .dog)
        pet.owner = client
        context.insert(client)
        context.insert(pet)
        try context.save()

        let suite = "StoreHealthCheckTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let index = RecordingSpotlightIndex()
        let indexer = SpotlightIndexer(index: index, defaults: defaults, debounceInterval: .milliseconds(10))
        indexer.applyPrivacyPolicy(allowsIndexing: true)

        let outcome = await StoreHealthCheck.clearAuxiliaryCaches(container: container, spotlight: indexer).value

        XCTAssertEqual(outcome, .completed(clients: 1, pets: 1))
        XCTAssertEqual(index.calls.first, .deleteAll, "The rebuild clears the index before re-adding.")
        XCTAssertEqual(
            Set(index.indexedItems.keys),
            ["client-\(client.uuid.uuidString)", "pet-\(pet.uuid.uuidString)"],
            "Clearing caches must leave Spotlight rebuilt, not empty."
        )
    }
}
