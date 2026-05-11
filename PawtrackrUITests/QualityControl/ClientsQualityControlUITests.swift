import XCTest

@MainActor
final class ClientsQualityControlUITests: QualityControlUITestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        launch(startTab: "clients")
    }

    func testClientsDirectLaunchShowsSeededOwner() throws {
        XCTAssertTrue(waitForClientsScreen(), "Clients screen did not load.")

        let rowVisible = waitForAny([
            { self.app.buttons["clients.row.UITest Owner"].exists },
            { self.app.staticTexts["UITest Owner"].exists }
        ], timeout: 8)

        XCTAssertTrue(rowVisible, "Seeded owner should be visible on direct Clients launch.")
    }

    func testClientsSearchFiltersSeededOwner() throws {
        XCTAssertTrue(waitForClientsScreen(), "Clients screen did not load.")

        _ = tapIfHittable(app.buttons["clients.toolbar.search"], timeout: 4)
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(waitUntilHittable(searchField, timeout: 5), "Search field should become hittable.")

        searchField.tap()
        searchField.typeText("UITest")

        XCTAssertTrue(
            waitForAny([
                { self.app.buttons["clients.row.UITest Owner"].exists },
                { self.app.staticTexts["UITest Owner"].exists }
            ], timeout: 6),
            "Searching for UITest should keep the seeded client discoverable."
        )

        replaceText(in: searchField, with: "")
        _ = tapIfHittable(app.buttons["Cancel"], timeout: 2)
    }

    func testNewClientSheetOpensAndCancels() throws {
        XCTAssertTrue(waitForClientsScreen(), "Clients screen did not load.")

        let addClient = app.buttons["clients.fab.addClient"]
        XCTAssertTrue(waitUntilHittable(addClient, timeout: 6), "Add Client button should be hittable.")
        addClient.tap()

        XCTAssertTrue(app.textFields["newClient.firstName"].waitForExistence(timeout: 6))
        _ = tapIfHittable(app.buttons["newClient.cancel"], timeout: 4)

        XCTAssertTrue(waitForClientsScreen(timeout: 6), "Clients screen should still be responsive after cancelling.")
    }
}
