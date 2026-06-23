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

    func testWalkthroughBackButtonReturnsToPreviousStepOnIPad() throws {
        launch(startWalkthrough: true)

        assertActiveWalkthroughAnchor("dashboard", timeout: 15)
        XCTAssertTrue(tapWalkthroughPrimary(timeout: 8), "Walkthrough Next should be tappable.")

        assertActiveWalkthroughAnchor("clients", timeout: 8)
        let back = app.buttons["walkthrough.back"]
        XCTAssertTrue(waitUntilHittable(back, timeout: 8), "Walkthrough Back should be tappable.")
        back.tap()

        assertActiveWalkthroughAnchor("dashboard", timeout: 8)
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

    func testClientDetailActionTargetsStayHittableAndOpenCheckoutOnIPad() throws {
        launch(startWalkthrough: true)

        advanceWalkthroughUntilActiveAnchor("cdAddPet", maxTaps: 20)
        assertActiveWalkthroughAnchor("cdAddPet")
        XCTAssertTrue(
            waitUntilHittable(app.buttons["clientDetail.addPet.inline"], timeout: 8),
            "The visible iPad Add Pet control should own the Add Pet walkthrough target."
        )

        advanceWalkthroughUntilActiveAnchor("cdCheckOut", maxTaps: 6)
        assertActiveWalkthroughAnchor("cdCheckOut")
        let checkoutButton = app.buttons["clientDetail.pet.UITest Pet.checkOut"]
        XCTAssertTrue(checkoutButton.waitForExistence(timeout: 8), "Checkout should be visible for the highlighted walkthrough target.")
        assertBubbleDoesNotCover(checkoutButton, named: "Check Out")
        XCTAssertTrue(
            waitUntilHittable(checkoutButton, timeout: 8),
            "Checkout should be highlighted without the overlay blocking taps. layout=\(activeWalkthroughLayoutDebug())"
        )
        checkoutButton.tap()

        assertActiveWalkthroughAnchor("coServices", timeout: 12)

        advanceWalkthroughUntilActiveAnchor("cdPetHistory", maxTaps: 8)
        assertActiveWalkthroughAnchor("cdPetHistory")
        XCTAssertTrue(
            waitUntilHittable(app.buttons["clientDetail.pet.UITest Pet.history"], timeout: 8),
            "The pet History button should be the highlighted, tappable target."
        )
        assertBubbleDoesNotCover(app.buttons["clientDetail.pet.UITest Pet.history"], named: "Pet History")

        advanceWalkthroughUntilActiveAnchor("cdHistory", maxTaps: 3)
        assertActiveWalkthroughAnchor("cdHistory")
    }

    func testSettingsWalkthroughDetailTargetsRenderOnIPad() throws {
        launch(startWalkthrough: true)

        advanceWalkthroughUntilActiveAnchor("setBusiness", maxTaps: 48)
        assertActiveWalkthroughAnchor("setBusiness")
        XCTAssertTrue(app.otherElements["walkthrough.bubble"].exists)
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
        XCTAssertTrue(stepCounter.label.hasPrefix("Step 1") || stepCounter.label.contains("1/") || stepCounter.label.contains("1 of"), "Step counter should show step 1 after replay")
    }

    private func advanceWalkthroughUntilNewClientOwnerForm(maxTaps: Int = 14) {
        let firstName = app.textFields["newClient.firstName"]
        for _ in 0..<maxTaps {
            if firstName.exists { return }

            if tapWalkthroughPrimary(timeout: 4) {
                // Synchronize by waiting for the UI state to change: either the firstName field appears
                // or the next button disappears/changes, avoiding a fixed sleep.
                if firstName.waitForExistence(timeout: 2) { return }
                continue
            }

            if firstName.waitForExistence(timeout: 3) { return }
        }
        XCTFail("Walkthrough did not present the New Client owner form.")
    }

    private func advanceWalkthroughUntilActiveAnchor(_ anchor: String, maxTaps: Int) {
        let target = app.otherElements["walkthrough.activeAnchor.\(anchor)"]
        for _ in 0..<maxTaps {
            if target.exists { return }

            if app.otherElements["walkthrough.activeAnchor.cdCheckIn"].exists {
                let checkIn = app.buttons["clientDetail.pet.UITest Pet.checkIn"]
                if waitUntilHittable(checkIn, timeout: 2) {
                    checkIn.tap()
                    if target.waitForExistence(timeout: 4) { return }
                }
            }

            if app.otherElements["walkthrough.activeAnchor.cdCheckOut"].exists {
                let checkOut = app.buttons["clientDetail.pet.UITest Pet.checkOut"]
                if waitUntilHittable(checkOut, timeout: 2) {
                    checkOut.tap()
                    if target.waitForExistence(timeout: 4) { return }
                }
            }

            if tapWalkthroughPrimary(timeout: 4) {
                if target.waitForExistence(timeout: 3) { return }
                continue
            }

            if target.waitForExistence(timeout: 3) { return }
        }
        XCTFail("Walkthrough did not reach active anchor \(anchor).")
    }

    private func tapWalkthroughPrimary(timeout: TimeInterval = 4) -> Bool {
        let primary = app.buttons["walkthrough.primary"]
        if waitUntilHittable(primary, timeout: timeout) {
            primary.tap()
            return true
        }

        guard primary.exists, primary.frame.width > 4, primary.frame.height > 4 else {
            return false
        }

        primary.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        return true
    }

    private func assertActiveWalkthroughAnchor(_ anchor: String, timeout: TimeInterval = 8) {
        XCTAssertTrue(
            app.otherElements["walkthrough.activeAnchor.\(anchor)"].waitForExistence(timeout: timeout),
            "Walkthrough should expose active anchor \(anchor)."
        )
        XCTAssertTrue(
            app.otherElements["walkthrough.bubble"].waitForExistence(timeout: timeout),
            "Walkthrough bubble should be visible for active anchor \(anchor)."
        )
    }

    private func activeWalkthroughLayoutDebug() -> String {
        app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH %@", "walkthrough.activeAnchor.")).firstMatch.value as? String ?? "no layout debug"
    }

    private func assertBubbleDoesNotCover(
        _ element: XCUIElement,
        named name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let bubble = app.otherElements["walkthrough.bubble"]
        XCTAssertTrue(bubble.waitForExistence(timeout: 4), "Walkthrough bubble should be visible before checking \(name).", file: file, line: line)
        XCTAssertTrue(element.exists, "\(name) target should exist before checking bubble overlap.", file: file, line: line)
        let debugValue = activeWalkthroughLayoutDebug()
        XCTAssertFalse(
            bubble.frame.intersects(element.frame),
            "Walkthrough bubble should not cover the highlighted \(name) target. bubble=\(bubble.frame) target=\(element.frame) layout=\(debugValue)",
            file: file,
            line: line
        )
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
