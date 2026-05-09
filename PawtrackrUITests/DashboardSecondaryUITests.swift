//
//  DashboardSecondaryUITests.swift
//  PawtrackrUITests
//
//  Drives the Dashboard's secondary surfaces: quick actions, deep-links,
//  scrollable rows. Complements PawtrackrUITests which already covers core flow.
//

import XCTest

@MainActor
final class DashboardSecondaryUITests: XCTestCase {
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

    // MARK: - Quick actions

    func testQuickAction_NewClient_OpensSheet() throws {
        waitForDashboard()

        let action = app.buttons["dashboard.quickAction.newClient"]
        let scroll = app.scrollViews["dashboard.scroll"]
        for _ in 0..<5 where !action.exists {
            scroll.exists ? scroll.swipeUp() : app.swipeUp()
        }

        XCTAssertTrue(action.waitForHittable(timeout: 8), "Quick action New Client button must exist.")
        action.tap()

        XCTAssertTrue(app.textFields["newClient.firstName"].waitForExistence(timeout: 6),
                      "New Client sheet should open from Dashboard quick action.")

        // Cancel out so other tests start clean.
        app.buttons["newClient.cancel"].tap()
    }

    func testQuickAction_Reports_NavigatesToInsights() throws {
        waitForDashboard()

        let action = app.buttons["dashboard.quickAction.reports"]
        let scroll = app.scrollViews["dashboard.scroll"]
        for _ in 0..<5 where !action.exists {
            scroll.exists ? scroll.swipeUp() : app.swipeUp()
        }
        XCTAssertTrue(action.waitForHittable(timeout: 8), "Reports quick action must exist.")
        action.tap()

        XCTAssertTrue(app.staticTexts["Revenue"].waitForExistence(timeout: 10),
                      "Reports quick action should land on Insights screen.")
    }

    func testQuickAction_CheckIn_NavigatesToClients() throws {
        waitForDashboard()

        let action = app.buttons["dashboard.quickAction.checkIn"]
        let scroll = app.scrollViews["dashboard.scroll"]
        for _ in 0..<5 where !action.exists {
            scroll.exists ? scroll.swipeUp() : app.swipeUp()
        }
        XCTAssertTrue(action.waitForHittable(timeout: 8))
        action.tap()

        let landed = waitForAny([
            { self.app.staticTexts["UITest Owner"].exists },
            { self.app.staticTexts["Welcome Back!"].exists },
            { self.app.navigationBars["Clients"].exists }
        ], timeout: 8)
        XCTAssertTrue(landed, "Check-In quick action should bring up Clients tab.")
    }

    // MARK: - Active session row

    func testActiveSessionRowAppearsAndHasCheckoutButton() throws {
        waitForDashboard()

        let scroll = app.scrollViews["dashboard.scroll"]
        let target = scroll.exists ? scroll : app.scrollViews.firstMatch
        var found = false
        for _ in 0..<6 {
            if app.buttons["dashboard.activeSession.checkoutButton"].exists { found = true; break }
            if target.exists { target.swipeUp() } else { app.swipeUp() }
        }
        XCTAssertTrue(found, "Active session row's checkout button should be present (seeded data).")
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
