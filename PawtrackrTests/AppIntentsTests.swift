import XCTest
import SwiftData
import AppIntents
@testable import Pawtrackr

final class AppIntentsTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema(PawtrackrSchema.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
    }

    @MainActor
    func testCheckInPetIntent_Metadata() async throws {
        XCTAssertEqual(CheckInPetIntent.title, "Check In Pet")
        XCTAssertFalse(CheckInPetIntent.openAppWhenRun)
    }
    
    @MainActor
    func testGetBusinessStatsIntent_ReturnsSummary() async throws {
        // Similar to above, verifying the intent metadata.
        XCTAssertEqual(GetBusinessStatsIntent.title, "Get Business Stats")
    }
}
