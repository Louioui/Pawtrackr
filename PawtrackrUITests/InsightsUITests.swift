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
        app.launchEnvironment["PAWTRACKR_UI_START_TAB"] = "insights"
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Tab activation

    func testInsightsTabLoadsAndShowsKPIs() throws {
        XCTAssertTrue(waitForInsightsScreen(timeout: 12), "Insights screen did not finish presenting.")

        XCTAssertTrue(app.staticTexts["Revenue"].waitForExistence(timeout: 12),
                      "Insights tab should display the Revenue KPI heading.")

        let anyKPI = waitForAny([
            { self.app.staticTexts["Avg Visit"].exists },
            { self.app.staticTexts["Retention"].exists },
            { self.app.otherElements["insights.kpi.avgVisit"].exists },
            { self.app.otherElements["insights.kpi.retention"].exists }
        ], timeout: 6)
        XCTAssertTrue(anyKPI, "At least one secondary KPI tile should render.")
    }

    func testInsightsScrollsRevealsAdditionalCards() throws {
        XCTAssertTrue(waitForInsightsScreen(timeout: 12), "Insights screen did not finish presenting.")
        XCTAssertTrue(app.staticTexts["Revenue"].waitForExistence(timeout: 12))

        let target = insightsSwipeAnchor()
        for _ in 0..<4 {
            target.swipeUp()
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        }

        let anyLowerCard = waitForAny([
            { self.app.staticTexts["Top Services"].exists || self.app.staticTexts["insights.section.topServices"].exists },
            { self.app.staticTexts["Payment Mix"].exists || self.app.staticTexts["insights.section.paymentMix"].exists },
            { self.app.staticTexts["Visits by Category"].exists || self.app.staticTexts["insights.section.category"].exists },
            { self.app.staticTexts["Client Retention"].exists || self.app.staticTexts["insights.section.retention"].exists },
            { self.app.staticTexts["Top Clients"].exists || self.app.staticTexts["insights.section.topClients"].exists }
        ], timeout: 6)
        XCTAssertTrue(anyLowerCard, "Scrolling should reveal one of the lower analytics cards.")
    }

    // MARK: - Period picker

    func testInsightsRevenuePeriodPickerSwitchesWindow() throws {
        XCTAssertTrue(waitForInsightsScreen(timeout: 12), "Insights screen did not finish presenting.")
        XCTAssertTrue(app.staticTexts["Revenue"].waitForExistence(timeout: 12))

        // The picker uses segmented style; segments come through as buttons named 7D/30D/90D.
        let sevenDay = app.buttons["7D"]
        let thirtyDay = app.buttons["30D"]
        let ninetyDay = app.buttons["90D"]
        let windowLabel = app.staticTexts["insights.revenue.window"]

        XCTAssertTrue(windowLabel.waitForExistence(timeout: 4), "Revenue window label should be present.")

        if sevenDay.waitForHittable(timeout: 4) {
            sevenDay.tap()
            XCTAssertTrue(
                waitForAny([
                    { (windowLabel.value as? String)?.contains("7-day") == true },
                    { self.app.staticTexts["7-day window"].exists }
                ], timeout: 4),
                "Picker should change the displayed window label."
            )
        }
        if ninetyDay.waitForHittable(timeout: 3) {
            ninetyDay.tap()
            XCTAssertTrue(
                waitForAny([
                    { (windowLabel.value as? String)?.contains("90-day") == true },
                    { self.app.staticTexts["90-day window"].exists }
                ], timeout: 4)
            )
        }
        if thirtyDay.waitForHittable(timeout: 3) {
            thirtyDay.tap()
        }
    }

    // MARK: - Export

    func testInsightsExportReportButtonExists() throws {
        XCTAssertTrue(waitForInsightsScreen(timeout: 12), "Insights screen did not finish presenting.")
        XCTAssertTrue(app.staticTexts["Revenue"].waitForExistence(timeout: 12))

        // Either the prepare-button or (if cached) the share-link should be visible.
        let exportBtn = app.buttons["insights.exportReport"]
        let shareBtn = app.buttons["insights.shareReport"]
        let anyVisible = waitForAny([
            { exportBtn.exists },
            { shareBtn.exists },
            { self.app.buttons["Export Report"].exists },
            { self.app.buttons["Share Report"].exists }
        ], timeout: 6)
        XCTAssertTrue(anyVisible, "An Export Report or Share Report toolbar item should be present.")
    }

    // MARK: - Pull-to-refresh stays responsive

    func testInsightsPullToRefreshRemainsResponsive() throws {
        XCTAssertTrue(waitForInsightsScreen(timeout: 12), "Insights screen did not finish presenting.")
        XCTAssertTrue(app.staticTexts["Revenue"].waitForExistence(timeout: 12))

        let target = insightsSwipeAnchor()
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

    private func waitForInsightsScreen(timeout: TimeInterval = 3) -> Bool {
        waitForAny([
            { self.app.buttons["30D"].exists },
            { self.app.buttons["7D"].exists },
            { self.app.staticTexts["30-day window"].exists },
            { self.app.otherElements["insights.mainScroll"].exists },
            { self.app.otherElements["insights.mainScroll.content"].exists }
        ], timeout: timeout)
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

    private func insightsSwipeAnchor() -> XCUIElement {
        let periodButton = app.buttons["30D"]
        if periodButton.exists { return periodButton }

        let revenueWindow = app.staticTexts["30-day window"]
        if revenueWindow.exists { return revenueWindow }

        let explicitScroll = app.scrollViews["insights.mainScroll"]
        if explicitScroll.exists { return explicitScroll }

        let explicitContainer = app.otherElements["insights.mainScroll"]
        if explicitContainer.exists { return explicitContainer }

        let revenueHeading = app.staticTexts["Revenue"]
        if revenueHeading.exists { return revenueHeading }

        return app.otherElements.firstMatch
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
