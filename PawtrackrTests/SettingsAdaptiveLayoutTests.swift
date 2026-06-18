import XCTest
@testable import Pawtrackr

final class SettingsAdaptiveLayoutTests: XCTestCase {
    func testCompactSettingsDetailUsesTighterPaddingAndFitsAvailableWidth() {
        let width: CGFloat = 460

        XCTAssertLessThanOrEqual(SettingsAdaptiveLayout.detailHorizontalPadding(for: width), 20)
        XCTAssertLessThanOrEqual(SettingsAdaptiveLayout.contentMaxWidth(for: width), width)
        XCTAssertTrue(SettingsAdaptiveLayout.usesCompactSettingsNavigator(availableWidth: width))
    }

    func testWideSettingsDetailCapsReadableContentWidth() {
        let width: CGFloat = 1_500

        XCTAssertEqual(SettingsAdaptiveLayout.detailHorizontalPadding(for: width), 30)
        XCTAssertEqual(SettingsAdaptiveLayout.contentMaxWidth(for: width), 940)
        XCTAssertFalse(SettingsAdaptiveLayout.usesCompactSettingsNavigator(availableWidth: width))
    }
}
