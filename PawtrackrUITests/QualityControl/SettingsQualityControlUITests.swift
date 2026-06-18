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
            { self.app.buttons["settings.section.security"].exists },
            { self.app.buttons["settings.section.dataExport"].exists },
            { self.app.buttons["settings.exportClients"].exists }
        ], timeout: 6)

        XCTAssertTrue(sectionsVisible, "Security and export controls should be present on direct Settings launch.")
    }

    func testDisableAppLockConfirmationCanCancel() throws {
        XCTAssertTrue(waitForSettingsScreen(), "Settings screen did not load.")
        openSettingsSection(identifier: "security", title: "Security")

        let toggle = app.switches["settings.appLockToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 6), "App Lock toggle must be present.")

        ensureAppLockEnabledWithPIN()
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
        openSettingsSection(identifier: "dataExport", title: "Data Export")

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

    private func openSettingsSection(identifier: String, title: String) {
        if identifier == "security", app.switches["settings.appLockToggle"].exists {
            return
        }
        if identifier == "dataExport",
           app.buttons["settings.exportClients"].exists || app.buttons["settings.exportVisits"].exists {
            return
        }

        let sectionButton = app.buttons["settings.section.\(identifier)"]
        if waitUntilHittable(sectionButton, timeout: 4) {
            sectionButton.tap()
            return
        }

        let sectionTitle = app.staticTexts[title]
        if waitUntilHittable(sectionTitle, timeout: 2) {
            sectionTitle.tap()
        }
    }

    private func ensureAppLockEnabledWithPIN() {
        let toggle = app.switches["settings.appLockToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 6), "App Lock toggle must be present.")
        if toggle.value as? String == "1" { return }

        toggle.tap()
        XCTAssertTrue(waitForAny([
            { self.app.navigationBars["Set PIN"].exists },
            { self.app.staticTexts["Set PIN"].exists },
            { self.app.secureTextFields["settings.pin.new"].exists }
        ], timeout: 6), "Enabling App Lock without a saved PIN should ask for an initial PIN.")

        let newPIN = app.secureTextFields["settings.pin.new"]
        let confirmPIN = app.secureTextFields["settings.pin.confirm"]
        XCTAssertTrue(waitUntilHittable(newPIN, timeout: 4), "New PIN field should be hittable.")
        newPIN.tap()
        newPIN.typeText("2468")
        XCTAssertTrue(waitUntilHittable(confirmPIN, timeout: 4), "Confirm PIN field should be hittable.")
        confirmPIN.tap()
        confirmPIN.typeText("2468")

        let save = app.buttons["settings.pin.save"].exists ? app.buttons["settings.pin.save"] : app.buttons["Save"]
        XCTAssertTrue(waitUntilHittable(save, timeout: 4), "PIN save button should be hittable.")
        save.tap()

        XCTAssertTrue(waitForAny([
            { toggle.value as? String == "1" },
            { self.app.buttons["settings.changePIN"].exists }
        ], timeout: 8), "Saving the initial PIN should enable App Lock.")
    }
}
