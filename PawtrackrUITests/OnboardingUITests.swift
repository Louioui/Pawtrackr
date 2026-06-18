//
//  OnboardingUITests.swift
//  PawtrackrUITests
//
//  Drives the multi-step onboarding flow end-to-end against a launch where the
//  UI test seeder skips seeding so the onboarding sheet takes over the screen.
//

import XCTest

@MainActor
final class OnboardingUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "-pawtrackr-ui-testing",
            "-pawtrackr-ui-onboarding",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launchEnvironment["PAWTRACKR_UI_TESTING"] = "1"
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Welcome → Business Profile

    func testWelcomeStepShowsAndContinueAdvances() {
        XCTAssertTrue(
            app.staticTexts["Welcome to Pawtrackr"].waitForExistence(timeout: 12),
            "Welcome step did not appear — onboarding launch flag may not be wired."
        )
        let continueBtn = app.buttons["onboarding.continue"]
        XCTAssertTrue(continueBtn.waitForHittable(timeout: 5))
        continueBtn.tap()

        XCTAssertTrue(
            app.staticTexts["Business Profile"].waitForExistence(timeout: 5)
                || app.textFields["onboarding.businessName"].waitForExistence(timeout: 5),
            "Continue from welcome should land on Business Profile."
        )
    }

    // MARK: - Business Profile validation

    func testBusinessProfileBlocksEmptyName() {
        advanceFromWelcome()

        let nameField = app.textFields["onboarding.businessName"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))

        let continueBtn = app.buttons["onboarding.continue"]
        XCTAssertTrue(continueBtn.exists)
        // The button is disabled — tapping should not advance us off this step.
        continueBtn.tap()
        XCTAssertTrue(nameField.exists, "Business profile step should still be visible.")
    }

    func testBusinessProfileAcceptsNameAndAdvances() {
        advanceFromWelcome()

        let nameField = app.textFields["onboarding.businessName"]
        XCTAssertTrue(nameField.waitForHittable(timeout: 5))
        nameField.tap()
        nameField.typeText("Pawtrackr UI Test Shop")

        app.keyboards.buttons["Done"].tapIfExists()

        let continueBtn = app.buttons["onboarding.continue"]
        XCTAssertTrue(continueBtn.waitForHittable(timeout: 3))
        continueBtn.tap()

        XCTAssertTrue(
            waitForRegionalStep(),
            "Should land on contact information step after providing a business name."
        )
    }

    // MARK: - Full happy path

    func testFullOnboardingFlow_StartFresh_PersistsAndDismissesSheet() {
        advanceFromWelcome()

        // Business
        let nameField = app.textFields["onboarding.businessName"]
        XCTAssertTrue(nameField.waitForHittable(timeout: 5))
        nameField.tap()
        nameField.typeText("UITest Shop")
        app.keyboards.buttons["Done"].tapIfExists()

        tapOnboardingContinue()

        // Contact information — leave defaults, tap Continue
        XCTAssertTrue(waitForRegionalStep())
        tapOnboardingContinue()

        // Security — type both PINs
        XCTAssertTrue(
            app.staticTexts["Set Your App PIN"].waitForExistence(timeout: 5)
                || app.staticTexts["Security"].waitForExistence(timeout: 5)
        )
        let pinField = app.textFields["onboarding.pinField"]
        let confirmPinField = app.textFields["onboarding.confirmPinField"]

        if pinField.waitForExistence(timeout: 5) {
            pinField.tap()
            pinField.typeText("1234")
        }
        if confirmPinField.waitForExistence(timeout: 3) {
            confirmPinField.tap()
            confirmPinField.typeText("1234")
        }

        tapOnboardingContinue()

        // Permissions — tap Continue (Review Setup)
        XCTAssertTrue(
            app.staticTexts["Choose Your Defaults"].waitForExistence(timeout: 5)
                || app.staticTexts["Permissions"].waitForExistence(timeout: 5)
        )
        tapOnboardingContinue()

        // Finish — tap Explore Pawtrackr
        XCTAssertTrue(
            app.staticTexts["You're all set!"].waitForExistence(timeout: 5)
                || app.staticTexts["Finish"].waitForExistence(timeout: 5)
        )
        let explore = app.buttons["onboarding.explore"]
        XCTAssertTrue(explore.waitForHittable(timeout: 5))
        explore.tap()

        // After finish, the dashboard or PIN gate should appear (not the welcome step).
        let landed = waitForAny([
            { self.app.staticTexts["Dashboard"].exists },
            { self.app.navigationBars["Dashboard"].exists },
            { self.app.staticTexts["Enter PIN"].exists }
        ], timeout: 25)

        XCTAssertTrue(landed, "Onboarding should dismiss and the app shell should appear.")
        XCTAssertFalse(
            app.staticTexts["Welcome to Pawtrackr"].exists,
            "Onboarding should be dismissed once finish completes."
        )
    }

    // MARK: - Helpers

    private func advanceFromWelcome() {
        XCTAssertTrue(
            app.staticTexts["Welcome to Pawtrackr"].waitForExistence(timeout: 12)
        )
        let continueBtn = app.buttons["onboarding.continue"]
        XCTAssertTrue(continueBtn.waitForHittable(timeout: 5))
        continueBtn.tap()
    }

    private func tapOnboardingContinue() {
        let continueBtn = app.buttons["onboarding.continue"]
        XCTAssertTrue(continueBtn.waitForHittable(timeout: 6),
                      "Continue button should be hittable.")
        continueBtn.tap()
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

    private func waitForAny(_ conditions: [() -> Bool], timeout: TimeInterval) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if conditions.contains(where: { $0() }) { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        }
        return conditions.contains(where: { $0() })
    }
}

// MARK: - XCUIElement extensions

private extension XCUIElement {
    func waitForHittable(timeout: TimeInterval) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if exists && isHittable { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return exists && isHittable
    }

    @discardableResult
    func tapIfExists(timeout: TimeInterval = 0) -> Bool {
        if timeout > 0 { _ = waitForHittable(timeout: timeout) }
        guard exists && isHittable else { return false }
        tap()
        return true
    }
}
