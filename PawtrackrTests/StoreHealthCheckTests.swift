import XCTest
import SwiftData
@testable import Pawtrackr

final class StoreHealthCheckTests: XCTestCase {
    var container: ModelContainer!
    
    override func setUpWithError() throws {
        let schema = Schema(PawtrackrSchema.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
    }

    func testIsStoreHealthy_ReturnsTrueForValidContainer() {
        let healthy = StoreHealthCheck.isStoreHealthy(container: container)
        XCTAssertTrue(healthy)
    }
    
    func testRepairStore_DoesNotCrash() {
        // Repair store clears caches and indexes. We verify it executes without error.
        StoreHealthCheck.repairStore()
        XCTAssertTrue(true)
    }
}
