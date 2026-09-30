import XCTest
import SwiftData
@testable import Pawtrackr

final class LocalStoreConfigurationTests: XCTestCase {
    func testProductionConfigurationPreservesExistingNamedStoreLocation() {
        let schema = Schema(PawtrackrSchema.models)
        let configuration = LocalStoreConfiguration.make(schema: schema)
        let existingNamedStore = ModelConfiguration("Pawtrackr", schema: schema, cloudKitDatabase: .none)

        XCTAssertEqual(configuration.name, "Pawtrackr")
        XCTAssertEqual(configuration.url, existingNamedStore.url)
        XCTAssertFalse(configuration.isStoredInMemoryOnly)
        XCTAssertNil(configuration.cloudKitContainerIdentifier)
    }

    @MainActor
    func testInMemoryFacadeUsesLocalConfiguration() throws {
        let store = DataStoreService(inMemory: true)
        let configuration = try XCTUnwrap(store.container.configurations.first)

        XCTAssertEqual(configuration.name, "PawtrackrTests")
        XCTAssertTrue(configuration.isStoredInMemoryOnly)
        XCTAssertNil(configuration.cloudKitContainerIdentifier)

        store.container.mainContext.insert(Client(firstName: "Local", lastName: "Client"))
        try store.container.mainContext.save()
        let clients: [Client] = try store.fetch()
        XCTAssertEqual(clients.map(\.firstName), ["Local"])
    }
}
