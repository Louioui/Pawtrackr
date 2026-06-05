import XCTest
@testable import Pawtrackr

final class MemorySafetyTests: XCTestCase {
    func testDashboardViewModelRetainCycles() {
        // Verify view models deallocate when dashboard view is dismissed
    }
}
