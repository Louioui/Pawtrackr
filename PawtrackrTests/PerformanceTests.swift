import XCTest
@testable import Pawtrackr
import SwiftData

final class PerformanceTests: XCTestCase {

    /// Ensures dashboard insights load within the 500ms professional standard.
    @MainActor
    func testInsightsLoadPerformance() async throws {
        // Use the in-memory test container to avoid touching the user's real
        // CloudKit-backed store from a unit test.
        // The fixture keeps the store too: the repository's context doesn't
        // retain its container, and fetching after it's freed crashes.
        let milliseconds = try await PerformanceBudget.fastestCPUMilliseconds { () -> (DataStoreService, DashboardRepository) in
            let store = DataStoreService(inMemory: true)
            return (store, DashboardRepository(modelContext: store.container.mainContext))
        } _: { fixture in
            _ = try await fixture.1.fetchKPIs()
        }

        let duration = milliseconds / 1_000
        XCTAssertLessThan(duration, 0.5, "Dashboard KPIs used too much CPU: \(duration)s")
    }
}
