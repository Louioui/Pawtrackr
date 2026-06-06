import XCTest
@testable import Pawtrackr
import SwiftData

final class PerformanceTests: XCTestCase {

    /// Ensures dashboard insights load within the 500ms professional standard.
    @MainActor
    func testInsightsLoadPerformance() async throws {
        // Use the in-memory test container to avoid touching the user's real
        // CloudKit-backed store from a unit test.
        let store = DataStoreService(inMemory: true)
        let repo = DashboardRepository(modelContext: store.container.mainContext)

        let start = CFAbsoluteTimeGetCurrent()
        _ = try await repo.fetchKPIs()
        let end = CFAbsoluteTimeGetCurrent()

        let duration = end - start
        XCTAssertLessThan(duration, 0.5, "Dashboard KPIs took too long: \(duration)s")
    }
}
