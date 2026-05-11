import XCTest

@MainActor
final class CheckoutQualityControlUITests: QualityControlUITestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        launch()
    }

    func testCreditPaymentShowsReferenceValidationImmediately() throws {
        openCheckoutFromDashboard()

        XCTAssertTrue(app.staticTexts["Pick the services"].waitForExistence(timeout: 8))
        _ = tapIfHittable(app.buttons["checkout.service.Haircut"], timeout: 8)

        tapPrimaryButton(named: "Continue to Notes")
        XCTAssertTrue(app.staticTexts["Add notes and photos"].waitForExistence(timeout: 8))

        tapPrimaryButton(named: "Continue to Payment")
        XCTAssertTrue(app.staticTexts["Confirm payment"].waitForExistence(timeout: 8))

        let credit = app.buttons["checkout.payment.creditCard"]
        XCTAssertTrue(waitUntilHittable(credit, timeout: 5))
        credit.tap()

        let validation = app.staticTexts["checkout.referenceValidation"]
        XCTAssertTrue(validation.waitForExistence(timeout: 5), "Credit payments should require a reference immediately.")
    }

    func testPaymentMethodSwitchingDoesNotFreezeCheckout() throws {
        openCheckoutFromDashboard()

        XCTAssertTrue(app.staticTexts["Pick the services"].waitForExistence(timeout: 8))
        _ = tapIfHittable(app.buttons["checkout.service.Bath"], timeout: 8)

        tapPrimaryButton(named: "Continue to Notes")
        tapPrimaryButton(named: "Continue to Payment")

        XCTAssertTrue(app.staticTexts["Confirm payment"].waitForExistence(timeout: 8))

        _ = tapIfHittable(app.buttons["checkout.payment.creditCard"], timeout: 5)
        _ = tapIfHittable(app.buttons["checkout.payment.cash"], timeout: 5)
        _ = tapIfHittable(app.buttons["checkout.payment.zelle"], timeout: 5)

        XCTAssertTrue(
            waitForAny([
                { self.app.textFields["checkout.amountField"].exists },
                { self.app.staticTexts["Summary"].exists }
            ], timeout: 5),
            "Checkout payment step should remain interactive after switching methods."
        )
    }

    func testBackNavigationFromPaymentReturnsToNotes() throws {
        openCheckoutFromDashboard()

        XCTAssertTrue(app.staticTexts["Pick the services"].waitForExistence(timeout: 8))
        _ = tapIfHittable(app.buttons["checkout.service.Full Package"], timeout: 8)

        tapPrimaryButton(named: "Continue to Notes")
        tapPrimaryButton(named: "Continue to Payment")

        XCTAssertTrue(app.staticTexts["Confirm payment"].waitForExistence(timeout: 8))
        _ = tapIfHittable(app.buttons["checkout.backButton"], timeout: 5)

        XCTAssertTrue(app.staticTexts["Add notes and photos"].waitForExistence(timeout: 6))
    }
}
