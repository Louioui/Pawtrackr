import XCTest
@testable import Pawtrackr
import SwiftData

final class PerformanceTests: XCTestCase {

    /// Ensures dashboard insights load within the 500ms professional standard.
    @MainActor
    func testInsightsLoadPerformance() async throws {
        // Use the in-memory test container to avoid touching the user's real
        // CloudKit-backed store from a unit test.
        let milliseconds = try await PerformanceBudget.fastestMilliseconds { () -> DashboardRepository in
            let store = DataStoreService(inMemory: true)
            return DashboardRepository(modelContext: store.container.mainContext)
        } _: { repo in
            _ = try await repo.fetchKPIs()
        }

        let duration = milliseconds / 1_000
        XCTAssertLessThan(duration, 0.5, "Dashboard KPIs took too long: \(duration)s")
    }
}
