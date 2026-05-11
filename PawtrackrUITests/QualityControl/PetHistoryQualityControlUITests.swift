import XCTest

@MainActor
final class PetHistoryQualityControlUITests: QualityControlUITestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        launch(startTab: "clients")
    }

    func testPetHistoryOpensWithSearchAndListSurface() throws {
        openPetHistoryFromSeededClient()

        let historyVisible = waitForAny([
            { self.app.textFields["petHistory.search"].exists },
            { self.app.otherElements["petHistory.list"].exists },
            { self.app.buttons["petHistory.scope"].exists }
        ], timeout: 8)

        XCTAssertTrue(historyVisible, "Pet history should expose searchable, scrollable content.")
    }

    func testPetHistorySearchFiltersWithoutDismissingSheet() throws {
        openPetHistoryFromSeededClient()

        let searchField = app.textFields["petHistory.search"]
        XCTAssertTrue(waitUntilHittable(searchField, timeout: 6), "Pet history search should be hittable.")
        searchField.tap()
        searchField.typeText("Bath")
        dismissKeyboardIfPresent()

        XCTAssertTrue(
            waitForAny([
                { self.app.otherElements["petHistory.list"].exists },
                { self.app.staticTexts["No Matching Visits"].exists }
            ], timeout: 6),
            "Filtering pet history should keep the sheet responsive."
        )
    }

    func testPetHistoryScopeSwitchesWithoutBreakingLayout() throws {
        openPetHistoryFromSeededClient()

        let allButton = app.buttons["All"]
        let todayButton = app.buttons["Today"]

        XCTAssertTrue(allButton.waitForExistence(timeout: 6))
        if waitUntilHittable(todayButton, timeout: 4) {
            todayButton.tap()
        }
        if waitUntilHittable(allButton, timeout: 4) {
            allButton.tap()
        }

        XCTAssertTrue(
            waitForAny([
                { self.app.otherElements["petHistory.list"].exists },
                { self.app.buttons["petHistory.loadMore"].exists },
                { self.app.navigationBars["UITest Pet"].exists }
            ], timeout: 6),
            "Switching pet-history scopes should not break the view."
        )
    }
}
