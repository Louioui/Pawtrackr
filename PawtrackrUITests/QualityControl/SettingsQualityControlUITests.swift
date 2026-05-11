import XCTest

@MainActor
final class SettingsQualityControlUITests: QualityControlUITestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        launch(startTab: "settings")
    }

    func testSettingsDirectLaunchShowsSecurityAndExportSections() throws {
        XCTAssertTrue(waitForSettingsScreen(), "Settings screen did not load.")

        let sectionsVisible = waitForAny([
            { self.app.staticTexts["Security"].exists },
            { self.app.staticTexts["Data Export"].exists },
            { self.app.buttons["settings.exportClients"].exists }
        ], timeout: 6)

        XCTAssertTrue(sectionsVisible, "Security and export controls should be present on direct Settings launch.")
    }

    func testDisableAppLockConfirmationCanCancel() throws {
        XCTAssertTrue(waitForSettingsScreen(), "Settings screen did not load.")

        let toggle = app.switches["settings.appLockToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 6), "App Lock toggle must be present.")

        if toggle.value as? String == "0" {
            toggle.tap()
        }
        toggle.tap()

        let alertVisible = waitForAny([
            { self.app.alerts["Disable App Lock?"].exists },
            { self.app.alerts.element(boundBy: 0).exists }
        ], timeout: 5)
        XCTAssertTrue(alertVisible, "Disabling the lock should require confirmation.")

        _ = tapIfHittable(app.alerts.buttons["Cancel"], timeout: 3)
        XCTAssertEqual(toggle.value as? String, "1", "Cancelling should keep App Lock enabled.")
    }

    func testExportButtonsRemainReachableAfterScroll() throws {
        XCTAssertTrue(waitForSettingsScreen(), "Settings screen did not load.")

        let scroll = app.scrollViews.firstMatch
        for _ in 0..<4 {
            if app.buttons["settings.exportClients"].exists && app.buttons["settings.exportVisits"].exists {
                break
            }
            if scroll.exists {
                scroll.swipeUp()
            } else {
                app.swipeUp()
            }
        }

        XCTAssertTrue(waitUntilHittable(app.buttons["settings.exportClients"], timeout: 6))
        XCTAssertTrue(waitUntilHittable(app.buttons["settings.exportVisits"], timeout: 6))
    }
}
