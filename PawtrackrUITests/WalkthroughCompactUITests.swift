import XCTest

@MainActor
final class WalkthroughCompactUITests: QualityControlUITestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        XCUIDevice.shared.orientation = .portrait
    }

    func testRecentHistoryStepKeepsGuideReadableOnIPhone() throws {
        launch(startWalkthrough: true)

        advanceWalkthroughUntilActiveAnchor("cdHistory", maxTaps: 36)
        assertActiveWalkthroughAnchor("cdHistory")

        let bubble = app.otherElements["walkthrough.bubble"]
        XCTAssertTrue(bubble.waitForExistence(timeout: 8), "Recent History walkthrough bubble should be visible.")

        let screen = app.windows.firstMatch.frame
        XCTAssertGreaterThanOrEqual(
            bubble.frame.height,
            240,
            "Step 24 should leave enough visible bubble height for the guide text. layout=\(activeWalkthroughLayoutDebug())"
        )
        XCTAssertGreaterThanOrEqual(bubble.frame.minY, screen.minY)
        XCTAssertLessThanOrEqual(
            bubble.frame.maxY,
            screen.maxY,
            "Step 24 guide should not be clipped below the iPhone screen. layout=\(activeWalkthroughLayoutDebug())"
        )
    }

    private func advanceWalkthroughUntilActiveAnchor(_ anchor: String, maxTaps: Int) {
        let target = app.otherElements["walkthrough.activeAnchor.\(anchor)"]
        for _ in 0..<maxTaps {
            if target.exists { return }

            if app.otherElements["walkthrough.activeAnchor.cdCheckIn"].exists {
                let checkIn = app.buttons["clientDetail.pet.UITest Pet.checkIn"]
                if tapVisible(checkIn, timeout: 2), target.waitForExistence(timeout: 4) { return }
            }

            if app.otherElements["walkthrough.activeAnchor.cdCheckOut"].exists {
                let checkOut = app.buttons["clientDetail.pet.UITest Pet.checkOut"]
                if tapVisible(checkOut, timeout: 2), target.waitForExistence(timeout: 4) { return }
            }

            if tapWalkthroughPrimary(timeout: 4) {
                if target.waitForExistence(timeout: 3) { return }
                continue
            }

            if target.waitForExistence(timeout: 3) { return }
        }
        XCTFail("Walkthrough did not reach active anchor \(anchor).")
    }

    private func tapWalkthroughPrimary(timeout: TimeInterval = 4) -> Bool {
        tapVisible(app.buttons["walkthrough.primary"].firstMatch, timeout: timeout)
    }

    private func tapVisible(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        if waitUntilHittable(element, timeout: timeout) {
            element.tap()
            return true
        }

        guard element.exists, element.frame.width > 4, element.frame.height > 4 else {
            return false
        }

        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        return true
    }

    private func assertActiveWalkthroughAnchor(_ anchor: String, timeout: TimeInterval = 8) {
        XCTAssertTrue(
            app.otherElements["walkthrough.activeAnchor.\(anchor)"].waitForExistence(timeout: timeout),
            "Walkthrough should expose active anchor \(anchor)."
        )
        XCTAssertTrue(
            app.otherElements["walkthrough.bubble"].waitForExistence(timeout: timeout),
            "Walkthrough bubble should be visible for active anchor \(anchor)."
        )
    }

    private func activeWalkthroughLayoutDebug() -> String {
        app.otherElements
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "walkthrough.activeAnchor."))
            .firstMatch
            .value as? String ?? "no layout debug"
    }
}
