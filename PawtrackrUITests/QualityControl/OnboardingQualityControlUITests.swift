import XCTest

@MainActor
final class OnboardingQualityControlUITests: QualityControlUITestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        launch(onboarding: true)
    }

    func testBackNavigationFromRegionalReturnsToBusiness() throws {
        XCTAssertTrue(app.staticTexts["Welcome to Pawtrackr"].waitForExistence(timeout: 12))
        _ = tapIfHittable(app.buttons["onboarding.continue"], timeout: 5)

        let nameField = app.textFields["onboarding.businessName"]
        XCTAssertTrue(waitUntilHittable(nameField, timeout: 5))
        nameField.tap()
        nameField.typeText("QC Grooming")
        dismissKeyboardIfPresent()

        _ = tapIfHittable(app.buttons["onboarding.continue"], timeout: 4)
        XCTAssertTrue(waitForRegionalStep(), "Regional/contact step should appear.")

        _ = tapIfHittable(app.buttons["onboarding.back"], timeout: 4)
        XCTAssertTrue(app.textFields["onboarding.businessName"].waitForExistence(timeout: 5))
    }

    func testPinMismatchBlocksAdvancingToPermissions() throws {
        advanceToSecurityStep()

        let pinField = app.textFields["onboarding.pinField"]
        let confirmField = app.textFields["onboarding.confirmPinField"]

        XCTAssertTrue(pinField.waitForExistence(timeout: 5))
        pinField.tap()
        pinField.typeText("1234")
        confirmField.tap()
        confirmField.typeText("9999")

        XCTAssertTrue(app.staticTexts["PINs do not match."].waitForExistence(timeout: 4))
        XCTAssertFalse(app.staticTexts["Choose Your Defaults"].exists, "Mismatched PINs should block the next step.")
    }

    func testDemoDataPathDismissesOnboarding() throws {
        advanceToWarmStartStep()

        let demoData = app.buttons["onboarding.demoData"]
        XCTAssertTrue(waitUntilHittable(demoData, timeout: 6))
        demoData.tap()

        let landed = waitForAny([
            { self.app.staticTexts["Dashboard"].exists },
            { self.app.navigationBars["Dashboard"].exists },
            { self.app.staticTexts["Enter PIN"].exists }
        ], timeout: 25)

        XCTAssertTrue(landed, "Demo-data onboarding path should land in the main app shell.")
        XCTAssertFalse(app.staticTexts["Welcome to Pawtrackr"].exists)
    }

    private func advanceToSecurityStep() {
        XCTAssertTrue(app.staticTexts["Welcome to Pawtrackr"].waitForExistence(timeout: 12))
        _ = tapIfHittable(app.buttons["onboarding.continue"], timeout: 5)

        let nameField = app.textFields["onboarding.businessName"]
        XCTAssertTrue(waitUntilHittable(nameField, timeout: 5))
        nameField.tap()
        nameField.typeText("QC Grooming")
        dismissKeyboardIfPresent()

        _ = tapIfHittable(app.buttons["onboarding.continue"], timeout: 4)
        XCTAssertTrue(waitForRegionalStep(), "Regional/contact step should appear.")
        _ = tapIfHittable(app.buttons["onboarding.continue"], timeout: 4)
        XCTAssertTrue(app.staticTexts["Set Your App PIN"].waitForExistence(timeout: 5))
    }

    private func waitForRegionalStep(timeout: TimeInterval = 5) -> Bool {
        waitForAny([
            { self.app.staticTexts["Contact Information"].exists },
            { self.app.staticTexts["Regional Info"].exists },
            { self.app.staticTexts["Contact Email"].exists },
            {
                let title = self.app.staticTexts["onboarding.stepTitle"]
                return title.exists && ["Contact Information", "Regional Info"].contains(title.label)
            }
        ], timeout: timeout)
    }

    private func advanceToWarmStartStep() {
        advanceToSecurityStep()

        let pinField = app.textFields["onboarding.pinField"]
        let confirmField = app.textFields["onboarding.confirmPinField"]

        pinField.tap()
        pinField.typeText("1234")
        confirmField.tap()
        confirmField.typeText("1234")

        _ = tapIfHittable(app.buttons["onboarding.continue"], timeout: 4)
        XCTAssertTrue(app.staticTexts["Choose Your Defaults"].waitForExistence(timeout: 5))
        _ = tapIfHittable(app.buttons["onboarding.continue"], timeout: 4)
        XCTAssertTrue(app.staticTexts["How would you like to start?"].waitForExistence(timeout: 5))
    }
}
