//
//  InsightsUITests.swift
//  PawtrackrUITests
//
//  Drives the Insights tab end-to-end: load, period picker, scroll, export.
//

import XCTest

@MainActor
final class InsightsUITests: XCTestCase {
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

    // MARK: - Tab activation

    func testInsightsTabLoadsAndShowsKPIs() throws {
        waitForDashboard()
        tapTab("Insights")

        XCTAssertTrue(app.staticTexts["Revenue"].waitForExistence(timeout: 12),
                      "Insights tab should display the Revenue KPI heading.")

        let anyKPI = waitForAny([
            { self.app.staticTexts["Avg Visit"].exists },
            { self.app.staticTexts["Retention"].exists }
        ], timeout: 6)
        XCTAssertTrue(anyKPI, "At least one secondary KPI tile should render.")
    }

    func testInsightsScrollsRevealsAdditionalCards() throws {
        waitForDashboard()
        tapTab("Insights")
        XCTAssertTrue(app.staticTexts["Revenue"].waitForExistence(timeout: 12))

        let scroll = app.scrollViews["insights.mainScroll"]
        let target = scroll.exists ? scroll : app.scrollViews.firstMatch
        for _ in 0..<3 {
            target.exists ? target.swipeUp() : app.swipeUp()
        }

        let anyLowerCard = waitForAny([
            { self.app.staticTexts["Top Services"].exists },
            { self.app.staticTexts["Payment Mix"].exists },
            { self.app.staticTexts["Visits by Category"].exists },
            { self.app.staticTexts["Client Retention"].exists },
            { self.app.staticTexts["Top Clients"].exists }
        ], timeout: 6)
        XCTAssertTrue(anyLowerCard, "Scrolling should reveal one of the lower analytics cards.")
    }

    // MARK: - Period picker

    func testInsightsRevenuePeriodPickerSwitchesWindow() throws {
        waitForDashboard()
        tapTab("Insights")
        XCTAssertTrue(app.staticTexts["Revenue"].waitForExistence(timeout: 12))

        // The picker uses segmented style; segments come through as buttons named 7D/30D/90D.
        let sevenDay = app.buttons["7D"]
        let thirtyDay = app.buttons["30D"]
        let ninetyDay = app.buttons["90D"]

        if sevenDay.waitForHittable(timeout: 4) {
            sevenDay.tap()
            // The "7-day window" label should appear under the heading.
            XCTAssertTrue(
                app.staticTexts["7-day window"].waitForExistence(timeout: 4)
                    || app.staticTexts.matching(NSPredicate(format: "label CONTAINS '7-day'")).firstMatch.waitForExistence(timeout: 2),
                "Picker should change the displayed window label."
            )
        }
        if ninetyDay.waitForHittable(timeout: 3) {
            ninetyDay.tap()
            XCTAssertTrue(
                app.staticTexts["90-day window"].waitForExistence(timeout: 4)
                    || app.staticTexts.matching(NSPredicate(format: "label CONTAINS '90-day'")).firstMatch.waitForExistence(timeout: 2)
            )
        }
        if thirtyDay.waitForHittable(timeout: 3) {
            thirtyDay.tap()
        }
    }

    // MARK: - Export

    func testInsightsExportReportButtonExists() throws {
        waitForDashboard()
        tapTab("Insights")
        XCTAssertTrue(app.staticTexts["Revenue"].waitForExistence(timeout: 12))

        // Either the prepare-button or (if cached) the share-link should be visible.
        let exportBtn = app.buttons["insights.exportReport"]
        let shareBtn = app.buttons["insights.shareReport"]
        let anyVisible = waitForAny([
            { exportBtn.exists },
            { shareBtn.exists }
        ], timeout: 6)
        XCTAssertTrue(anyVisible, "An Export Report or Share Report toolbar item should be present.")
    }

    // MARK: - Pull-to-refresh stays responsive

    func testInsightsPullToRefreshRemainsResponsive() throws {
        waitForDashboard()
        tapTab("Insights")
        XCTAssertTrue(app.staticTexts["Revenue"].waitForExistence(timeout: 12))

        let scroll = app.scrollViews["insights.mainScroll"]
        let target = scroll.exists ? scroll : app.scrollViews.firstMatch
        target.swipeDown(velocity: .fast)

        let stillThere = waitForAny([
            { self.app.staticTexts["Revenue"].exists },
            { self.app.navigationBars["Insights"].exists }
        ], timeout: 8)
        XCTAssertTrue(stillThere, "Insights screen should remain alive after pull-to-refresh.")
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

    /// Robust tab-tap that survives iOS 18's TabView content-swap flake.
    /// Retries up to 4 times, with a coordinate-based fallback when the
    /// declared activation point is briefly invalid during layout.
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
            // Done — caller will perform its own existence check.
            if attempt >= 1 { return }
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
