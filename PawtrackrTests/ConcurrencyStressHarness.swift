import XCTest
import SwiftData
@testable import Pawtrackr

/// Stress-tests SwiftData concurrency by hammering the repository with simultaneous requests.
final class ConcurrencyStressHarness: XCTDataTestCase {
    
    func testRepository_UnderExtremeConcurrentLoad() async throws {
        let repo = ClientRepository(modelContainer: container)
        
        // 1. Kick off 50 simultaneous creations
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                group.addTask {
                    _ = try? await repo.createClient(
                        firstName: "Stress",
                        lastName: "Test \(i)",
                        phone: "555\(String(format: "%04d", i))",
                        email: "",
                        address: "",
                        pets: [],
                        contacts: []
                    )
                }
            }
        }
        
        // 2. Simultaneously fetch while creations are finishing
        let fetchTask = Task {
            return try await repo.fetchClients(query: "", limit: 100, offset: 0)
        }
        
        let ids = try await fetchTask.value
        XCTAssertEqual(ids.count, 50, "All 50 clients should have been created successfully.")
    }
}
