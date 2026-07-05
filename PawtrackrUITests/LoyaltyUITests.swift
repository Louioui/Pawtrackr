//
//  LoyaltyUITests.swift
//  PawtrackrUITests
//
//  Focused UI coverage for the premium loyalty gate and rewards catalog.
//

import XCTest

@MainActor
final class LoyaltyUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testNonPremiumLoyaltyEntryShowsPaywallAfterDismissedLaunchPaywall() throws {
        launch(entitlement: .notEntitled)
        XCTAssertTrue(app.staticTexts["Elevate Pawtrackr"].waitForExistence(timeout: 8))

        let dismiss = app.buttons["subscriptionPaywall.dismiss"]
        XCTAssertTrue(dismiss.waitForExistence(timeout: 6))
        dismiss.tap()

        openSeededClient()
        tapLoyaltyEntry()

        XCTAssertTrue(app.staticTexts["Elevate Pawtrackr"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["subscriptionPaywall.dismiss"].exists)
    }

    func testPremiumCanAdjustPointsAndRedeemReward() throws {
        launch(entitlement: .premium)
        openSeededClient()

        tapLoyaltyEntry()
        XCTAssertTrue(app.staticTexts["Loyalty & Rewards"].waitForExistence(timeout: 8))

        let adjust = app.buttons["clientLoyalty.adjustPoints"]
        XCTAssertTrue(adjust.waitForHittable(timeout: 6))
        adjust.tap()

        let pointsField = app.textFields["loyaltyAdjustment.pointsField"]
        XCTAssertTrue(pointsField.waitForHittable(timeout: 6))
        pointsField.tap()
        pointsField.typeText("100")

        let apply = app.buttons["loyaltyAdjustment.apply"]
        XCTAssertTrue(app.waitUntilHittable(apply, timeout: 6))
        apply.tap()

        XCTAssertTrue(waitForAny([
            { self.app.staticTexts["100"].exists },
            { self.app.staticTexts["100 points"].exists }
        ], timeout: 8))

        let redeemRewards = app.buttons["clientLoyalty.redeemRewards"]
        XCTAssertTrue(redeemRewards.waitForHittable(timeout: 6))
        redeemRewards.tap()

        XCTAssertTrue(app.staticTexts["Rewards Catalog"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.otherElements["rewardsCatalog.balance"].waitForExistence(timeout: 4)
                      || app.staticTexts["100 points"].waitForExistence(timeout: 4))
        let salonCreditReward = app.buttons["rewardsCatalog.reward.salon-credit-10.redeem"]
        XCTAssertTrue(salonCreditReward.waitForHittable(timeout: 6))
        salonCreditReward.tap()

        XCTAssertTrue(waitForAny([
            { self.app.otherElements["rewardsCatalog.status"].exists },
            { self.app.staticTexts["Redeemed $10 Salon Credit"].exists }
        ], timeout: 8))
        XCTAssertFalse(salonCreditReward.isEnabled)
    }

    private enum EntitlementLaunch {
        case notEntitled
        case premium
    }

    private func launch(entitlement: EntitlementLaunch) {
        app = XCUIApplication()
        app.launchArguments = [
            "--uitesting",
            "-pawtrackr-ui-testing",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launchEnvironment["PAWTRACKR_UI_TESTING"] = "1"
        switch entitlement {
        case .notEntitled:
            app.launchArguments.append("--mock-storekit-not-entitled")
        case .premium:
            app.launchArguments.append("--mock-storekit-premium")
            app.launchEnvironment["PAWTRACKR_UI_TESTING_PREMIUM"] = "1"
        }
        app.launch()
    }

    private func openSeededClient() {
        XCTAssertTrue(waitForDashboard(), "Dashboard did not load.")
        tapTab("Clients")

        let row = app.buttons["clients.row.UITest Owner"]
        let staticRow = app.staticTexts["UITest Owner"]

        if row.waitForHittable(timeout: 8) {
            row.tap()
        } else if staticRow.waitForHittable(timeout: 4) {
            staticRow.tap()
        } else {
            XCTFail("Could not find seeded client row.")
        }
    }

    private func tapLoyaltyEntry() {
        let loyaltyEntry = app.descendants(matching: .any)["clientDetail.loyaltyRewards"]
        let labeledEntry = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Loyalty and rewards")).firstMatch
        let scrollView = app.scrollViews.firstMatch

        for _ in 0..<8 {
            if loyaltyEntry.exists && loyaltyEntry.isHittable {
                loyaltyEntry.tap()
                return
            }
            if labeledEntry.exists && labeledEntry.isHittable {
                labeledEntry.tap()
                return
            }
            if scrollView.exists {
                scrollView.swipeUp()
            } else {
                app.swipeUp()
            }
        }

        XCTAssertTrue(loyaltyEntry.waitForHittable(timeout: 4) || labeledEntry.waitForHittable(timeout: 4),
                      "Loyalty entry should be hittable on the seeded client detail screen.")
        if loyaltyEntry.exists && loyaltyEntry.isHittable {
            loyaltyEntry.tap()
        } else {
            labeledEntry.tap()
        }
    }

    private func waitForDashboard(timeout: TimeInterval = 12) -> Bool {
        waitForAny([
            { self.app.staticTexts["Dashboard"].exists },
            { self.app.navigationBars["Dashboard"].exists }
        ], timeout: timeout)
    }

    private func tapTab(_ title: String) {
        let tab = app.tabBars.buttons[title]
        XCTAssertTrue(tab.waitForHittable(timeout: 8), "\(title) tab was not hittable.")
        tab.tap()
    }

    @discardableResult
    private func waitForAny(_ conditions: [() -> Bool], timeout: TimeInterval) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if conditions.contains(where: { $0() }) { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        }
        return conditions.contains(where: { $0() })
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

private extension XCUIApplication {
    func waitUntilHittable(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if element.exists && element.isHittable { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return element.exists && element.isHittable
    }
}
