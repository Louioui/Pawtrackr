import XCTest

@MainActor
final class ProWorkflowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testSettingsShowsLoyaltySection() throws {
        launch()
        openSurface(tab: "Settings", sidebarIdentifier: "sidebar.row.settings")

        let loyaltyVisible = waitForAny([
            { self.app.staticTexts["Loyalty"].exists },
            { self.app.buttons["settings.section.loyalty"].exists }
        ], timeout: 8)
        XCTAssertTrue(loyaltyVisible, "Settings should expose the loyalty management section.")
    }

    func testInsightsScreenStillLoads() throws {
        launch()
        openSurface(tab: "Insights", sidebarIdentifier: "sidebar.row.insights")

        let insightsVisible = waitForAny([
            { self.app.staticTexts["Insights"].exists },
            { self.app.navigationBars["Insights"].exists },
            { self.app.otherElements["insights.mainScroll"].exists },
            { self.app.buttons["30D"].exists }
        ], timeout: 8)
        XCTAssertTrue(insightsVisible, "Insights should still load after pro workflow scene additions.")
    }

    private func launch() {
        app = XCUIApplication()
        app.launchArguments = [
            "--uitesting",
            "-pawtrackr-ui-testing",
            "--mock-storekit-premium",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launchEnvironment["PAWTRACKR_UI_TESTING"] = "1"
        app.launchEnvironment["PAWTRACKR_UI_TESTING_PREMIUM"] = "1"
        app.launch()
    }

    private func openSurface(tab: String, sidebarIdentifier: String) {
        let tabButton = app.tabBars.buttons[tab]
        if tabButton.waitForHittable(timeout: 6) {
            tabButton.tap()
            return
        }

        let sidebarButton = app.buttons[sidebarIdentifier]
        XCTAssertTrue(sidebarButton.waitForHittable(timeout: 8), "\(tab) navigation entry was not hittable.")
        sidebarButton.tap()
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
