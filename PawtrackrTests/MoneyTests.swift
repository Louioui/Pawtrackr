import XCTest
@testable import Pawtrackr

final class MoneyTests: XCTestCase {
    
    func testRoundedMoney_UsesBankersRounding() {
        // Banker's rounding rounds to the nearest even number for .5 cases
        let val1 = Decimal(string: "10.255")!
        XCTAssertEqual(val1.roundedMoney(), Decimal(string: "10.26")!)
        
        let val2 = Decimal(string: "10.245")!
        XCTAssertEqual(val2.roundedMoney(), Decimal(string: "10.24")!)
        
        let val3 = Decimal(string: "10.254")!
        XCTAssertEqual(val3.roundedMoney(), Decimal(string: "10.25")!)
    }
    
    func testSafeAddition_RoundsResult() {
        let a = Decimal(string: "10.255")!
        let b = Decimal(string: "0.001")!
        // 10.255 + 0.001 = 10.256 -> rounds to 10.26
        XCTAssertEqual(a +~ b, Decimal(string: "10.26")!)
    }
    
    func testSafeMultiplication_RoundsResult() {
        let price = Decimal(string: "10.25")!
        let tax = Decimal(string: "0.0825")!
        // 10.25 * 0.0825 = 0.845625 -> rounds to 0.85
        XCTAssertEqual(price *~ tax, Decimal(string: "0.85")!)
    }
}
