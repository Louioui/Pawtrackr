import XCTest

@MainActor
final class WalkthroughIPadStressUITests: QualityControlUITestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    override func tearDownWithError() throws {
        XCUIDevice.shared.orientation = .portrait
        try super.tearDownWithError()
    }

    func testWalkthroughLaunchFlagStartsTourAndSurvivesIPadRotation() throws {
        launch(startWalkthrough: true)

        XCTAssertTrue(app.otherElements["walkthrough.card"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["walkthrough.stepCounter"].waitForExistence(timeout: 6))
        let initialStepText = app.staticTexts["walkthrough.stepCounter"].label
        XCTAssertFalse(initialStepText.isEmpty, "Step counter should have content")

        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.otherElements["walkthrough.card"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["walkthrough.stepCounter"].waitForExistence(timeout: 6))
        XCTAssertEqual(app.staticTexts["walkthrough.stepCounter"].label, initialStepText, "Step counter text should persist after portrait rotation")

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.otherElements["walkthrough.card"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["walkthrough.stepCounter"].label, initialStepText, "Step counter text should persist after landscape rotation")
        XCTAssertTrue(waitUntilHittable(app.buttons["walkthrough.primary"], timeout: 6))
    }

    func testWalkthroughContinuesIntoClientDetailsAfterCreatingClient() throws {
        launch(startWalkthrough: true)

        advanceWalkthroughUntilNewClientOwnerForm()

        let firstName = app.textFields["newClient.firstName"]
        XCTAssertTrue(waitUntilHittable(firstName, timeout: 10), "New Client owner form should be visible during the walkthrough.")
        firstName.tap()
        firstName.typeText("Tour")

        let lastName = app.textFields["newClient.lastName"]
        if waitUntilHittable(lastName, timeout: 3) {
            lastName.tap()
            lastName.typeText("Ipad")
        }
        dismissKeyboardIfPresent()

        let create = app.buttons["newClient.create"]
        XCTAssertTrue(waitUntilHittable(create, timeout: 8), "Create should be hittable after the walkthrough has introduced the owner form.")
        create.tap()

        XCTAssertTrue(app.staticTexts["Client Details"].waitForExistence(timeout: 12))
        XCTAssertTrue(waitForAny([
            { self.app.otherElements["walkthrough.card"].exists },
            { self.app.staticTexts["walkthrough.stepCounter"].exists }
        ], timeout: 12), "Walkthrough should continue after creating a client.")
        if app.staticTexts["walkthrough.stepCounter"].exists {
            XCTAssertFalse(app.staticTexts["walkthrough.stepCounter"].label.isEmpty, "Step counter should display progress information")
        }
    }

    func testSettingsReplayRestartsWalkthroughAfterSkip() throws {
        launch(startWalkthrough: true)

        XCTAssertTrue(waitUntilHittable(app.buttons["walkthrough.skip"], timeout: 15))
        app.buttons["walkthrough.skip"].tap()

        tapSettingsOnIPad()
        openAboutSettingsSection()

        let replayButton = app.buttons["settings.replayGettingStarted"]
        let settingsScroll = app.scrollViews.firstMatch
        for _ in 0..<6 where !replayButton.exists {
            settingsScroll.exists ? settingsScroll.swipeUp() : app.swipeUp()
        }

        XCTAssertTrue(waitUntilHittable(replayButton, timeout: 8), "Replay Getting Started should be visible in Settings.")
        replayButton.tap()

        let replayAlertButton = app.alerts.buttons["Replay"]
        XCTAssertTrue(waitUntilHittable(replayAlertButton, timeout: 5), "Replay confirmation should appear.")
        replayAlertButton.tap()

        XCTAssertTrue(app.otherElements["walkthrough.card"].waitForExistence(timeout: 12))
        let stepCounter = app.staticTexts["walkthrough.stepCounter"]
        XCTAssertTrue(stepCounter.waitForExistence(timeout: 6), "Step counter should appear after replay")
        XCTAssertTrue(stepCounter.label.contains("1"), "Step counter should show step 1 after replay")
    }

    private func advanceWalkthrough(untilStepPrefix expectedStepPrefix: String, maxTaps: Int = 16) {
        for _ in 0..<maxTaps {
            let counter = app.staticTexts["walkthrough.stepCounter"]
            if counter.exists, counter.label.hasPrefix(expectedStepPrefix) { return }

            let next = app.buttons["walkthrough.primary"]
            XCTAssertTrue(waitUntilHittable(next, timeout: 8), "Walkthrough primary button should remain hittable.")
            next.tap()
            
            // Wait for UI to update after tap to avoid race condition in next iteration
            _ = counter.waitForExistence(timeout: 2)
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
        XCTFail("Walkthrough did not reach step prefix \(expectedStepPrefix).")
    }

    private func advanceWalkthroughUntilNewClientOwnerForm(maxTaps: Int = 14) {
        let firstName = app.textFields["newClient.firstName"]
        for _ in 0..<maxTaps {
            if firstName.exists { return }

            let next = app.buttons["walkthrough.primary"]
            if waitUntilHittable(next, timeout: 4) {
                next.tap()
                // Synchronize by waiting for the UI state to change: either the firstName field appears
                // or the next button disappears/changes, avoiding a fixed sleep.
                if firstName.waitForExistence(timeout: 2) { return }
                continue
            }

            if firstName.waitForExistence(timeout: 3) { return }
        }
        XCTFail("Walkthrough did not present the New Client owner form.")
    }

    private func tapSettingsOnIPad() {
        let sidebarSettings = app.buttons["sidebar.row.settings"]
        if waitUntilHittable(sidebarSettings, timeout: 6) {
            sidebarSettings.tap()
            return
        }

        let tabSettings = app.tabBars.buttons["Settings"]
        XCTAssertTrue(waitUntilHittable(tabSettings, timeout: 6), "Settings navigation should be available.")
        tabSettings.tap()
    }

    private func openAboutSettingsSection() {
        let about = app.buttons["settings.section.about"]
        let settingsList = app.collectionViews.firstMatch
        for _ in 0..<6 where !about.exists {
            settingsList.exists ? settingsList.swipeUp() : app.swipeUp()
        }

        XCTAssertTrue(waitUntilHittable(about, timeout: 8), "About settings section should be visible.")
        about.tap()
    }
}
