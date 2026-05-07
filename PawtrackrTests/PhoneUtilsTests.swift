import XCTest
@testable import Pawtrackr

final class PhoneUtilsTests: XCTestCase {
    func testToE164_RejectsInvalidNANPNumbers() {
        XCTAssertNil(PhoneUtils.toE164("111-111-1111"))
        XCTAssertNil(PhoneUtils.toE164("012-555-0148"))
        XCTAssertNil(PhoneUtils.toE164("312-111-0148"))
        XCTAssertNil(PhoneUtils.toE164("312-555-0148-99"))
    }

    func testPhoneHelpers_AcceptValidNumberWithExtension() {
        let raw = "(312) 555-0148 x42"

        XCTAssertTrue(PhoneUtils.isValidUS(raw))
        XCTAssertEqual(PhoneUtils.toE164(raw), "+13125550148")
        XCTAssertEqual(PhoneUtils.display(raw), "(312) 555-0148 x42")
        XCTAssertEqual(PhoneUtils.displayMasked(raw), "(312) •••-0148")
        XCTAssertEqual(PhoneUtils.telURLString(raw), "tel:+13125550148")
        XCTAssertEqual(PhoneUtils.smsURLString(raw), "sms:+13125550148")
        XCTAssertEqual(PhoneUtils.whatsappURLString(raw), "https://wa.me/13125550148")
    }
}
