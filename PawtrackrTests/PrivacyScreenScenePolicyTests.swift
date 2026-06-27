import SwiftUI
import XCTest
@testable import Pawtrackr

final class PrivacyScreenScenePolicyTests: XCTestCase {
    func testPrivacyScreenCoversInactiveAndBackgroundSnapshots() {
        XCTAssertFalse(PrivacyScreenScenePolicy.shouldCoverContent(for: .active))
        XCTAssertTrue(PrivacyScreenScenePolicy.shouldCoverContent(for: .inactive))
        XCTAssertTrue(PrivacyScreenScenePolicy.shouldCoverContent(for: .background))
    }
}
