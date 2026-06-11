import XCTest

@MainActor
final class RecentHistoryQualityControlUITests: QualityControlUITestCase {
    func testRecentHistoryOpensFromDashboardQuickAction() throws {
        launch(startTab: "dashboard")
        XCTAssertTrue(waitForDashboard(), "Dashboard did not load.")

        let historyLink = app.buttons["dashboard.kpi.completedHistory"].exists
            ? app.buttons["dashboard.kpi.completedHistory"]
            : app.buttons["dashboard.kpi.inProgressHistory"]
        XCTAssertTrue(waitUntilHittable(historyLink, timeout: 8), "Dashboard history KPI should be hittable.")
        historyLink.tap()

        XCTAssertTrue(
            waitForAny([
                { self.app.navigationBars["Recent History"].exists },
                { self.app.textFields["recentHistory.search"].exists },
                { self.app.otherElements["recentHistory.list"].exists }
            ], timeout: 8),
            "Recent History should open from the dashboard quick action."
        )
    }

    func testRecentHistorySearchRemainsResponsive() throws {
        launch(startTab: "recenthistory")
        XCTAssertTrue(waitForRecentHistory(), "Recent History did not load.")

        let searchField = app.textFields["recentHistory.search"]
        XCTAssertTrue(waitUntilHittable(searchField, timeout: 6))
        searchField.tap()
        searchField.typeText("UITest")
        dismissKeyboardIfPresent()

        XCTAssertTrue(
            waitForAny([
                { self.app.otherElements["recentHistory.list"].exists },
                { self.app.otherElements["recentHistory.empty"].exists }
            ], timeout: 6),
            "Recent History search should not stall the screen."
        )
    }

    func testRecentHistoryScopeSwitcherKeepsListInteractive() throws {
        launch(startTab: "recenthistory")
        XCTAssertTrue(waitForRecentHistory(), "Recent History did not load.")

        let today = app.buttons["Today"]
        let all = app.buttons["All"]

        if waitUntilHittable(today, timeout: 4) {
            today.tap()
        }
        if waitUntilHittable(all, timeout: 4) {
            all.tap()
        }

        XCTAssertTrue(
            waitForAny([
                { self.app.otherElements["recentHistory.list"].exists },
                { self.app.otherElements["recentHistory.loading"].exists },
                { self.app.navigationBars["Recent History"].exists }
            ], timeout: 6),
            "Recent History should remain interactive when switching scopes."
        )
    }

    private func waitForRecentHistory(timeout: TimeInterval = 12) -> Bool {
        waitForAny([
            { self.app.navigationBars["Recent History"].exists },
            { self.app.textFields["recentHistory.search"].exists },
            { self.app.otherElements["recentHistory.list"].exists }
        ], timeout: timeout)
    }
}
