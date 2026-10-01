import XCTest

/// The client list on the heavy-load book (600 hostile clients plus the
/// poisoned ones: 10,000-character, Zalgo, invisible, bidi and emoji names)
/// at the largest accessibility text size, driven roughly: flick-scrolling,
/// fast typing, sort flips, double taps on a card and a cancelled swipe back.
@MainActor
final class ClientListChaosUITests: QualityControlUITestCase {
    private let sentinelRow = "clients.row.Stress Aaaa Sentinel"

    override func setUpWithError() throws {
        try super.setUpWithError()
        launch(
            startTab: "clients",
            scenario: "heavy_load",
            extraArguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        )
        XCTAssertTrue(waitForClientsScreen(timeout: 30), "Clients screen did not load with the heavy-load book.")
    }

    private var searchField: XCUIElement { app.searchFields.firstMatch }

    private func search(_ text: String) {
        _ = tapIfHittable(app.buttons["clients.toolbar.search"], timeout: 2)
        XCTAssertTrue(waitUntilHittable(searchField, timeout: 8), "Search field should become hittable.")
        replaceText(in: searchField, with: text)
    }

    private func assertStillRunning(_ step: String) {
        XCTAssertEqual(app.state, .runningForeground, "The app died after: \(step)")
    }

    func testFlickingTypingAndSortingThePoisonedBookAtTheLargestTextSize() throws {
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<12 { scroll.swipeUp(velocity: .fast) }
        for _ in 0..<12 { scroll.swipeDown(velocity: .fast) }
        assertStillRunning("flick scrolling")

        // Typed in one burst; the list must keep up without freezing.
        search("maria lopez de la cruz 🐶 محمد zalgo 312 555 0123 the quick brown fox")
        assertStillRunning("fast typing")

        search("Stress Aaaa")
        XCTAssertTrue(app.buttons[sentinelRow].waitForExistence(timeout: 10), "The sentinel client should be found.")
        XCTAssertEqual(app.buttons.matching(identifier: sentinelRow).count, 1, "The sentinel is listed twice.")

        // Flip the order while filtered: still exactly one sentinel row.
        let sortMenu = app.buttons["clients.sortMenu.inline"]
        for option in ["First Name", "Newest", "Last Name"] {
            XCTAssertTrue(tapIfHittable(sortMenu, timeout: 4), "Sort menu not reachable.")
            _ = tapIfHittable(app.buttons[option], timeout: 3)
            XCTAssertEqual(app.buttons.matching(identifier: sentinelRow).count, 1, "Sentinel repeated after sorting by \(option).")
        }

        search("")
        for _ in 0..<6 { scroll.swipeUp(velocity: .fast) }
        assertStillRunning("clearing the search and scrolling the full poisoned book")
    }

    /// Two taps on one card used to stack two client screens, so the first
    /// Back landed on the same client again instead of the list.
    func testDoubleTappedCardPushesOneScreenAndACancelledSwipeBackKeepsTheStackSane() throws {
        search("Stress Aaaa")
        let card = app.buttons[sentinelRow]
        XCTAssertTrue(waitUntilHittable(card, timeout: 10))

        card.doubleTap()
        XCTAssertTrue(app.buttons["clientDetail.editInline"].waitForExistence(timeout: 8), "Client screen did not open.")

        // Start a swipe back from the edge and let go a third of the way.
        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        edge.press(
            forDuration: 0.05,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)),
            withVelocity: .slow,
            thenHoldForDuration: 0.3
        )
        XCTAssertTrue(app.buttons["clientDetail.editInline"].waitForExistence(timeout: 4), "A cancelled swipe left the client screen.")

        // One Back reaches the list: there was one screen on the stack.
        let back = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(waitUntilHittable(back, timeout: 4))
        back.tap()
        XCTAssertTrue(waitUntilHittable(card, timeout: 8), "Back didn't return to the list: a second client screen was stacked.")

        // And the list still opens a client straight away.
        card.tap()
        XCTAssertTrue(app.buttons["clientDetail.editInline"].waitForExistence(timeout: 8))
        assertStillRunning("double tap, cancelled swipe back, reopen")
    }
}
