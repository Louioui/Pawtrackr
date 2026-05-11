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

    /// Regression test for the DashboardViewModel reactivity path.
    /// After a checkout completes, the eventBus emits `.checkoutCompleted`,
    /// DashboardViewModel.refresh() runs, and `activeVisits` becomes empty
    /// (the seeded run starts with exactly one active visit). If the
    /// observation task ever holds `self` strongly across the for-await
    /// suspension — as it did before the fix — the VM doesn't refresh and
    /// the active-session row stays visible, freezing the dashboard's view
    /// of state.
    func testActiveSessionDisappearsAfterCheckoutCompletes() throws {
        waitForDashboard()

        // Sanity: the seeded active session row must be present first.
        let checkoutButton = app.buttons["dashboard.activeSession.checkoutButton"]
        let scroll = app.scrollViews["dashboard.scroll"]
        var found = false
        for _ in 0..<6 {
            if checkoutButton.exists { found = true; break }
            if scroll.exists { scroll.swipeUp() } else { app.swipeUp() }
        }
        XCTAssertTrue(found, "Seeded active session row must exist before checkout.")

        // Complete a minimum-viable checkout: open from active session,
        // skip through the steps with default selections, confirm.
        XCTAssertTrue(checkoutButton.waitForHittable(timeout: 5))
        checkoutButton.tap()

        XCTAssertTrue(app.staticTexts["Pick the services"].waitForExistence(timeout: 8))
        let bath = app.buttons["checkout.service.Bath"]
        if bath.waitForHittable(timeout: 5) { bath.tap() }

        tapPrimaryButton(named: "Continue to Notes")
        tapPrimaryButton(named: "Continue to Payment")
        tapPrimaryButton(named: "Review Checkout")

        XCTAssertTrue(app.buttons["Confirm & Pay"].waitForHittable(timeout: 8))
        tapPrimaryButton(named: "Confirm & Pay")
        XCTAssertTrue(app.staticTexts["Checkout Complete!"].waitForExistence(timeout: 15))

        let doneButton = app.buttons["checkout.doneButton"]
        if doneButton.waitForHittable(timeout: 5) { doneButton.tap() }

        waitForDashboard()

        // The crucial assertion: the active-session checkout button must be
        // GONE within a reasonable refresh window. Before the fix, the
        // dashboard would not refresh and this would still be present.
        let disappeared = waitForCondition(timeout: 10) {
            !self.app.buttons["dashboard.activeSession.checkoutButton"].exists
        }
        XCTAssertTrue(
            disappeared,
            "Dashboard's active-session row should disappear after the only seeded active visit is checked out. If this fails, the eventBus → DashboardViewModel.refresh path is broken (likely a retain-cycle regression in the AsyncStream observer)."
        )
    }

    private func tapPrimaryButton(named title: String) {
        let titledButton = app.buttons[title]
        if titledButton.waitForHittable(timeout: 8) {
            titledButton.tap()
            return
        }
        let primaryButton = app.buttons["checkout.primaryButton"]
        XCTAssertTrue(primaryButton.waitForHittable(timeout: 8), "\(title) primary button was not hittable.")
        primaryButton.tap()
    }

    private func waitForCondition(timeout: TimeInterval, _ predicate: @escaping () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if predicate() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return predicate()
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
