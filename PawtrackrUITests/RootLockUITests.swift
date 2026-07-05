import XCTest

@MainActor
final class RootLockUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testOnboardingIsAllowedToRenderWhileStoreKitIsUnknown() throws {
        launch(arguments: ["--mock-storekit-unknown", "--is-first-launch", "-pawtrackr-ui-onboarding"])

        XCTAssertTrue(app.staticTexts["Welcome to Pawtrackr"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["Elevate Pawtrackr"].exists)
    }

    func testUnsubscribedUserCanDismissLaunchPaywallAndReadWorkspace() throws {
        launch(arguments: ["--mock-storekit-not-entitled", "--onboarding-complete"])

        XCTAssertTrue(app.staticTexts["Elevate Pawtrackr"].waitForExistence(timeout: 8))
        let dismiss = app.buttons["subscriptionPaywall.dismiss"]
        XCTAssertTrue(dismiss.waitForExistence(timeout: 6))
        dismiss.tap()

        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(
            app.staticTexts["Dashboard"].exists || app.navigationBars["Dashboard"].exists,
            "Dashboard should remain readable after dismissing the launch paywall."
        )
    }

    func testPremiumUserAutomaticallyBypassesLockToMainApp() throws {
        launch(arguments: ["--mock-storekit-premium", "--onboarding-complete"])

        XCTAssertFalse(app.staticTexts["Elevate Pawtrackr"].exists)
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 8))
    }

    private func launch(arguments: [String]) {
        app.launchArguments = [
            "--uitesting",
            "-pawtrackr-ui-testing",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ] + arguments
        app.launchEnvironment["PAWTRACKR_UI_TESTING"] = "1"
        app.launch()
    }
}
