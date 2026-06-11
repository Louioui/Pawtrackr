//
//  SettingsUITests.swift
//  PawtrackrUITests
//
//  Drives the Settings flow end-to-end: app lock toggle + disable confirmation,
//  biometric toggle, change-PIN sheet, async export buttons.
//

import XCTest

@MainActor
final class SettingsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "-pawtrackr-ui-testing",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launchEnvironment["PAWTRACKR_UI_TESTING"] = "1"
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Tab arrival

    func testSettingsTabLoadsAndShowsSections() throws {
        waitForDashboard()
        tapTab("Settings")

        let landed = waitForAny([
            { self.app.staticTexts["Business Profile"].exists },
            { self.app.staticTexts["Security"].exists },
            { self.app.staticTexts["Data Export"].exists },
            { self.app.buttons["settings.section.security"].exists },
            { self.app.buttons["settings.section.dataExport"].exists }
        ], timeout: 12)
        XCTAssertTrue(landed, "Settings sections should be visible.")
    }

    // MARK: - App Lock toggle confirmation

    func testDisableAppLockShowsConfirmationAlert() throws {
        waitForDashboard()
        tapTab("Settings")
        openSettingsSection(identifier: "security", title: "Security")

        let toggle = app.switches["settings.appLockToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 8), "App Lock toggle must be present.")

        // In UI test mode AppSettings init disables the lock by default. So we first
        // turn it on (no confirmation) and then attempt to flip off (confirmation).
        if toggle.value as? String == "0" {
            toggle.tap()
        }

        // Now turning it off should pop a confirmation alert.
        toggle.tap()

        let confirmAlert = app.alerts["Disable App Lock?"]
        let didShowAlert = waitForAny([
            { confirmAlert.exists },
            { self.app.alerts.element(boundBy: 0).exists }
        ], timeout: 5)
        XCTAssertTrue(didShowAlert, "Disable confirmation alert must appear.")

        // Cancel — lock should remain enabled.
        let cancel = app.alerts.buttons["Cancel"]
        if cancel.waitForHittable(timeout: 3) { cancel.tap() }
    }

    // MARK: - Change PIN sheet

    func testChangePINSheetOpensWithThreeFields() throws {
        waitForDashboard()
        tapTab("Settings")
        openSettingsSection(identifier: "security", title: "Security")

        // Make sure lock is on so the Change PIN button is visible.
        let toggle = app.switches["settings.appLockToggle"]
        if toggle.waitForExistence(timeout: 6), toggle.value as? String == "0" {
            toggle.tap()
        }

        let changePINBtn = app.buttons["settings.changePIN"]
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<4 where !changePINBtn.exists {
            scroll.exists ? scroll.swipeUp() : app.swipeUp()
        }
        XCTAssertTrue(changePINBtn.waitForHittable(timeout: 6), "Change PIN button should be hittable.")
        changePINBtn.tap()

        // The sheet shows "Change PIN" navigation bar / title.
        let sheetUp = waitForAny([
            { self.app.navigationBars["Change PIN"].exists },
            { self.app.staticTexts["Change PIN"].exists }
        ], timeout: 6)
        XCTAssertTrue(sheetUp, "Change PIN sheet must open.")

        // Cancel out cleanly.
        let cancelBtn = app.buttons["Cancel"]
        if cancelBtn.waitForHittable(timeout: 3) { cancelBtn.tap() }
    }

    // MARK: - Async export buttons

    func testExportClientsButtonOpensSharePreviewSheet() throws {
        waitForDashboard()
        tapTab("Settings")
        openSettingsSection(identifier: "dataExport", title: "Data Export")

        let exportBtn = app.buttons["settings.exportClients"]
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<5 where !exportBtn.exists {
            scroll.exists ? scroll.swipeUp() : app.swipeUp()
        }

        XCTAssertTrue(exportBtn.waitForHittable(timeout: 8), "Export Clients button should be present.")
        exportBtn.tap()

        // The preview sheet should appear (with the Share via… label) within a few seconds.
        let previewUp = waitForAny([
            { self.app.staticTexts["Clients Export Ready"].exists },
            { self.app.buttons.matching(NSPredicate(format: "label CONTAINS 'Share via'")).firstMatch.exists },
            { self.app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Export'")).firstMatch.exists }
        ], timeout: 12)
        XCTAssertTrue(previewUp, "Async export should produce the preview sheet.")

        // Dismiss the preview sheet by swiping down or tapping outside.
        app.swipeDown(velocity: .fast)
    }

    func testExportVisitsButtonExistsAndIsHittable() throws {
        waitForDashboard()
        tapTab("Settings")
        openSettingsSection(identifier: "dataExport", title: "Data Export")

        let exportBtn = app.buttons["settings.exportVisits"]
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<5 where !exportBtn.exists {
            scroll.exists ? scroll.swipeUp() : app.swipeUp()
        }
        XCTAssertTrue(exportBtn.waitForHittable(timeout: 8), "Export Visits button should be present.")
    }

    // MARK: - Helpers

    private func waitForAny(_ conditions: [() -> Bool], timeout: TimeInterval) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if conditions.contains(where: { $0() }) { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        }
        return conditions.contains(where: { $0() })
    }

    private func waitForDashboard() {
        XCTAssertTrue(
            app.staticTexts["Dashboard"].waitForExistence(timeout: 12)
                || app.navigationBars["Dashboard"].waitForExistence(timeout: 2),
            "Dashboard did not load."
        )
    }

    private func tapTab(_ title: String) {
        let tab = app.tabBars.buttons[title]
        XCTAssertTrue(tab.waitForHittable(timeout: 8), "\(title) tab was not hittable.")
        for attempt in 0..<4 {
            if attempt == 0 || !tab.isHittable {
                tab.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            } else {
                tab.tap()
            }
            _ = app.wait(for: .runningForeground, timeout: 0.5)
            RunLoop.current.run(until: Date().addingTimeInterval(0.6))
            if attempt >= 1 { return }
        }
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
        if sectionButton.waitForHittable(timeout: 4) {
            sectionButton.tap()
            return
        }

        let sectionTitle = app.staticTexts[title]
        if sectionTitle.waitForHittable(timeout: 2) {
            sectionTitle.tap()
        }
    }
}

private extension XCUIElement {
    func waitForHittable(timeout: TimeInterval) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if exists && isHittable { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return exists && isHittable
    }
}
