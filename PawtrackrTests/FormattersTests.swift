import XCTest
@testable import Pawtrackr

final class FormattersTests: XCTestCase {
    
    @MainActor
    func testCurrencyString_FormatsCorrectly() {
        Formatters.updateCurrencySymbol("$")
        let val = Decimal(string: "12.50")!
        XCTAssertEqual(Formatters.currencyString(val), "$12.50")
    }
    
    @MainActor
    func testParseCurrency_HandlesSloppyInput() {
        XCTAssertEqual(Formatters.parseCurrency("12.50"), Decimal(string: "12.50")!)
        XCTAssertEqual(Formatters.parseCurrency("$12.50"), Decimal(string: "12.50")!)
        XCTAssertEqual(Formatters.parseCurrency("$ 12, 50"), Decimal(string: "12.50")!)
        XCTAssertEqual(Formatters.parseCurrency("abc 12.50 def"), Decimal(string: "12.50")!)
    }
    
    @MainActor
    func testDurationString_FormatsCorrectly() {
        // Under a minute
        XCTAssertEqual(Formatters.durationString(seconds: 45), "45s")
        XCTAssertEqual(Formatters.durationString(seconds: 45, abbreviated: true), "45s")
        
        // Minutes
        XCTAssertEqual(Formatters.durationString(seconds: 120), "2 m 0 s")
        XCTAssertEqual(Formatters.durationString(seconds: 120, abbreviated: true), "2m0s")
        
        // Hours and Minutes
        XCTAssertEqual(Formatters.durationString(seconds: 3660), "1 h 1 m")
        XCTAssertEqual(Formatters.durationString(seconds: 3660, abbreviated: true), "1h1m")
    }
}
