import XCTest
@testable import Pawtrackr

final class SupportServicePrivacyTests: XCTestCase {
    func testSupportReportSanitizerRedactsCommonPIIFromDiagnostics() {
        let source = """
        Retry failed for ava.martinez@example.com at (312) 555-0100.
        Local file: /Users/Ava/Pawtrackr/Clients/Milo.pdf
        """

        let sanitized = SupportReportSanitizer.redacted(source)

        XCTAssertFalse(sanitized.contains("ava.martinez@example.com"))
        XCTAssertFalse(sanitized.contains("(312) 555-0100"))
        XCTAssertFalse(sanitized.contains("/Users/Ava"))
        XCTAssertTrue(sanitized.contains("<email>"))
        XCTAssertTrue(sanitized.contains("<phone>"))
        XCTAssertTrue(sanitized.contains("<path>"))
    }

    func testSupportReportDeviceTokenIsStableAndDoesNotExposeRawIdentifier() {
        let rawID = "D7CBB7F0-56B4-4F32-B901-E8CE2549021B"

        let first = SupportReportSanitizer.deviceToken(for: rawID)
        let second = SupportReportSanitizer.deviceToken(for: rawID)

        XCTAssertEqual(first, second)
        XCTAssertFalse(first.contains(rawID))
        XCTAssertFalse(first.isEmpty)
    }
}
