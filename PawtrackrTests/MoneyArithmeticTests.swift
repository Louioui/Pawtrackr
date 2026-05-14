import XCTest
import SwiftData
@testable import Pawtrackr

/// Decimal precision tests against real product math (Visit / VisitItem / Payment).
/// Complements MoneyTests.swift, which only covers the raw rounding helpers.
@MainActor
final class MoneyArithmeticTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema(PawtrackrSchema.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [config])
        context = container.mainContext
        Formatters.updateCurrencySymbol("$")
    }

    override func tearDownWithError() throws {
        container = nil
        context = nil
    }

    /// $65.00 base + $15.00 add-on must equal exactly $80.00 with no Double drift.
    func testVisitTotal_TwoServices_NoFloatingPointDrift() {
        let pet = makePet()
        let visit = Visit(pet: pet)
        context.insert(visit)

        visit.addItem(title: "Bath", unitPrice: Decimal(65))
        visit.addItem(title: "Nail Trim", unitPrice: Decimal(15))

        XCTAssertEqual(visit.servicesSubtotal, Decimal(string: "80.00"))
        XCTAssertEqual(visit.calculatedTotal, Decimal(string: "80.00"))
    }

    /// VisitItem.lineTotal must equal unitPrice × quantity exactly.
    func testVisitItem_LineTotalScalesByQuantityWithoutDrift() throws {
        let pet = makePet()
        let visit = Visit(pet: pet)
        context.insert(visit)
        visit.addItem(title: "Premium Wash", unitPrice: Decimal(string: "12.99")!, quantity: 3)

        let item = try XCTUnwrap(visit.items?.first)
        XCTAssertEqual(item.lineTotal, Decimal(string: "38.97"))
    }

    /// Ten $0.01 services must sum to exactly $0.10 — the classic FP-error trap.
    func testVisitTotal_TenPennies_StaysExact() {
        let pet = makePet()
        let visit = Visit(pet: pet)
        context.insert(visit)

        for _ in 0..<10 {
            visit.addItem(title: "Cent", unitPrice: Decimal(string: "0.01")!)
        }

        XCTAssertEqual(visit.calculatedTotal, Decimal(string: "0.10"))
    }

    /// Payment.amount must round-trip through SwiftData unchanged.
    func testPayment_AmountSurvivesPersistRoundTrip() throws {
        let pet = makePet()
        let visit = Visit(pet: pet)
        context.insert(visit)

        let payment = Payment(amount: Decimal(string: "123.45")!, method: .cash)
        context.insert(payment)
        visit.attachPayment(payment)
        try context.save()

        let visitUUID = visit.uuid
        let descriptor = FetchDescriptor<Visit>(predicate: #Predicate<Visit> { $0.uuid == visitUUID })
        let fetched = try XCTUnwrap(try context.fetch(descriptor).first)
        XCTAssertEqual(fetched.payment?.amount, Decimal(string: "123.45"))
    }

    /// Negative payment amounts must clamp to zero (Payment.init guard).
    func testPayment_RejectsNegativeAmounts() {
        let payment = Payment(amount: Decimal(-5), method: .cash)
        XCTAssertEqual(payment.amount, Decimal.zero)
    }

    /// Two-step Payment.setAmount must also clamp negatives.
    func testPayment_SetAmountClampsNegatives() {
        let payment = Payment(amount: 10, method: .cash)
        payment.setAmount(Decimal(string: "-7.5")!)
        XCTAssertEqual(payment.amount, Decimal.zero)
    }

    /// Visit.recalcTotal must overwrite a stale `total` with the line-item sum.
    func testVisit_RecalcTotal_OverwritesStaleValue() {
        let pet = makePet()
        let visit = Visit(pet: pet)
        context.insert(visit)
        visit.addItem(title: "Bath", unitPrice: Decimal(30))
        // Forcibly desync the stored total.
        visit.total = Decimal(string: "999.99")!
        visit.recalcTotal()
        XCTAssertEqual(visit.total, Decimal(string: "30.00"))
    }

    /// `moneyString` formatter must produce exactly two fractional digits with the active symbol.
    func testMoneyString_FormatsToTwoDecimalsWithSymbol() {
        let value: Decimal = 80
        XCTAssertEqual(value.moneyString, "$80.00")
    }

    /// Decimal/NSDecimalNumber round-trip must not drift for clean values.
    func testDecimal_NSDecimalNumberRoundTrip_NoDrift() throws {
        let original = try XCTUnwrap(Decimal(string: "999999.99"))
        let asNumber = NSDecimalNumber(decimal: original)
        XCTAssertEqual(asNumber.decimalValue, original)
    }

    private func makePet() -> Pet {
        let client = Client(firstName: "Test", lastName: "User", phone: "5550000000")
        context.insert(client)
        let pet = Pet(name: "Buddy", species: .dog)
        pet.owner = client
        context.insert(pet)
        return pet
    }
}
