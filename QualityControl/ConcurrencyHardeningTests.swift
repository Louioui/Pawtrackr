import XCTest
import SwiftData
import Combine
@testable import Pawtrackr

final class ConcurrencyHardeningTests: XCTestCase {

    func testActorSearchSafetyUnderPressure() async throws {
        let dataStore = DataStoreService(inMemory: true)
        let repo = ClientRepository(modelContainer: dataStore.container)
        
        // Stress test: 50 concurrent search requests
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                group.addTask {
                    _ = try? await repo.fetchClients(query: "Test \(i)", limit: 10, offset: 0)
                }
            }
        }
        // If we reach here without a crash or deadlock, actor serialization is working.
    }
    
    func testGlobalEventBusBroadcastIntegrity() async throws {
        let eventBus = GlobalEventBus()
        let expectation = XCTestExpectation(description: "All events received")
        expectation.expectedFulfillmentCount = 100
        
        let task = Task {
            for await _ in eventBus.stream {
                expectation.fulfill()
            }
        }
        
        // Stress test: 100 rapid broadcasts
        for _ in 0..<100 {
            eventBus.publish(.refreshRequired)
        }
        
        await fulfillment(of: [expectation], timeout: 2.0)
        task.cancel()
    }
    
    func testCrossActorDataContention() async throws {
        let dataStore = DataStoreService(inMemory: true)
        let clientRepo = ClientRepository(modelContainer: dataStore.container)
        let insightsActor = InsightsActor(modelContainer: dataStore.container)
        
        // Simulate simultaneous read/write from different actors
        let t1 = Task { try await clientRepo.fetchActiveClients(query: "") }
        let t2 = Task { try await insightsActor.fetchRevenue(periodDays: 30) }
        
        let _ = await (t1.value, t2.value)
        // Success if no SwiftData threading violations occur
    }
}
