import XCTest
@testable import Pawtrackr

final class MoneyTests: XCTestCase {
    
    func testRoundedMoney_UsesBankersRounding() {
        // Banker's rounding rounds to the nearest even number for .5 cases
        let val1: Decimal = 10.255
        XCTAssertEqual(val1.roundedMoney(), 10.26)
        
        let val2: Decimal = 10.245
        XCTAssertEqual(val2.roundedMoney(), 10.24)
        
        let val3: Decimal = 10.254
        XCTAssertEqual(val3.roundedMoney(), 10.25)
    }
    
    func testSafeAddition_RoundsResult() {
        let a: Decimal = 10.255
        let b: Decimal = 0.001
        // 10.255 + 0.001 = 10.256 -> rounds to 10.26
        XCTAssertEqual(a +~ b, 10.26)
    }
    
    func testSafeMultiplication_RoundsResult() {
        let price: Decimal = 10.25
        let tax: Decimal = 0.0825
        // 10.25 * 0.0825 = 0.845625 -> rounds to 0.85
        XCTAssertEqual(price *~ tax, 0.85)
    }
}
