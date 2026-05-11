import XCTest

@MainActor
final class InsightsQualityControlUITests: QualityControlUITestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        launch(startTab: "insights")
    }

    func testRevenueWindowAccessibilityValueTracksPicker() throws {
        XCTAssertTrue(waitForInsightsScreen(), "Insights screen did not finish presenting.")

        let windowLabel = app.staticTexts["insights.revenue.window"]
        let sevenDay = app.buttons["7D"]
        let ninetyDay = app.buttons["90D"]

        XCTAssertTrue(windowLabel.waitForExistence(timeout: 4))
        XCTAssertTrue(waitUntilHittable(sevenDay, timeout: 4))
        sevenDay.tap()

        XCTAssertTrue(
            waitForAny([
                { (windowLabel.value as? String)?.contains("7-day") == true },
                { self.app.staticTexts["7-day window"].exists }
            ], timeout: 4),
            "Revenue window should expose the 7-day selection."
        )

        XCTAssertTrue(waitUntilHittable(ninetyDay, timeout: 4))
        ninetyDay.tap()

        XCTAssertTrue(
            waitForAny([
                { (windowLabel.value as? String)?.contains("90-day") == true },
                { self.app.staticTexts["90-day window"].exists }
            ], timeout: 4),
            "Revenue window should expose the 90-day selection."
        )
    }

    func testInsightsScrollStillExposesLowerAnalyticsCards() throws {
        XCTAssertTrue(waitForInsightsScreen(), "Insights screen did not finish presenting.")

        let target = insightsSwipeAnchor()
        for _ in 0..<5 {
            target.swipeUp()
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }

        let reachedLowerCards = waitForAny([
            { self.app.otherElements["insights.section.topServices"].exists },
            { self.app.otherElements["insights.section.paymentMix"].exists },
            { self.app.otherElements["insights.section.category"].exists },
            { self.app.otherElements["insights.section.retention"].exists },
            { self.app.otherElements["insights.section.topClients"].exists }
        ], timeout: 6)

        XCTAssertTrue(reachedLowerCards, "Scrolling should reveal lower Insights cards.")
    }

    func testInsightsPullToRefreshKeepsToolbarAlive() throws {
        XCTAssertTrue(waitForInsightsScreen(), "Insights screen did not finish presenting.")

        insightsSwipeAnchor().swipeDown(velocity: .fast)

        let toolbarAlive = waitForAny([
            { self.app.buttons["insights.exportReport"].exists },
            { self.app.buttons["insights.shareReport"].exists },
            { self.app.buttons["Export Report"].exists },
            { self.app.buttons["Share Report"].exists }
        ], timeout: 8)

        XCTAssertTrue(toolbarAlive, "Insights toolbar actions should remain available after refresh.")
    }

    private func waitForInsightsScreen(timeout: TimeInterval = 12) -> Bool {
        waitForAny([
            { self.app.buttons["30D"].exists },
            { self.app.buttons["7D"].exists },
            { self.app.staticTexts["Revenue"].exists },
            { self.app.otherElements["insights.mainScroll"].exists }
        ], timeout: timeout)
    }

    private func insightsSwipeAnchor() -> XCUIElement {
        if app.buttons["30D"].exists { return app.buttons["30D"] }
        if app.staticTexts["Revenue"].exists { return app.staticTexts["Revenue"] }
        if app.otherElements["insights.mainScroll"].exists { return app.otherElements["insights.mainScroll"] }
        return app.otherElements.firstMatch
    }
}
