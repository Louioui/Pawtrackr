import XCTest
@testable import Pawtrackr

/// The rules every exported CSV follows (`CSVFormat`).
final class CSVFormatTests: XCTestCase {
    func testTextThatCouldRunAsAFormulaIsDefused() {
        XCTAssertEqual(CSVFormat.text("=1+2"), "'=1+2")
        XCTAssertEqual(CSVFormat.text("@SUM(A1)"), "'@SUM(A1)")
        XCTAssertEqual(CSVFormat.text("-5 lbs since June"), "'-5 lbs since June")
        XCTAssertEqual(CSVFormat.text("+cmd|' /C calc'!A0"), "'+cmd|' /C calc'!A0")
        XCTAssertEqual(CSVFormat.text("=HYPERLINK(\"http://x\")"), "\"'=HYPERLINK(\"\"http://x\"\")\"", "Still quoted and escaped.")
        XCTAssertEqual(CSVFormat.text("Bath"), "Bath")
        XCTAssertEqual(CSVFormat.text(nil), "")
    }

    func testPhonesReadAsTheAppShowsThem() {
        XCTAssertEqual(CSVFormat.phone("+14155550142"), "(415) 555-0142", "Not a number Excel would reformat.")
        XCTAssertEqual(CSVFormat.phone("4155550142"), "(415) 555-0142")
        XCTAssertEqual(CSVFormat.phone(nil), "")
        XCTAssertEqual(CSVFormat.phone("+44 20 7946 0958"), "'+44 20 7946 0958", "Numbers it can't format stay as typed, defused.")
    }

    func testNumbersArePlainAndSummable() throws {
        XCTAssertEqual(CSVFormat.money(try XCTUnwrap(Decimal(string: "1234.5"))), "1234.50")
        XCTAssertEqual(CSVFormat.money(try XCTUnwrap(Decimal(string: "1000000"))), "1000000.00", "No grouping separators.")
        XCTAssertEqual(CSVFormat.integer(7), "7")
        XCTAssertEqual(CSVFormat.percent(Decimal(25), of: Decimal(200)), "13")
        XCTAssertEqual(CSVFormat.percent(Decimal(25), of: .zero), "")
        XCTAssertEqual(CSVFormat.change(from: Decimal(50), to: Decimal(200)), "300")
        XCTAssertEqual(CSVFormat.change(from: Decimal(80), to: Decimal(60)), "-25")
        XCTAssertEqual(CSVFormat.change(from: .zero, to: Decimal(5)), "", "Nothing to compare with.")
    }

    func testDocumentsUseCRLFAndBlankLinesBetweenSections() {
        XCTAssertEqual(CSVFormat.document([["a", "b"], [], ["c"]]), "a,b\r\n\r\nc\r\n")
    }

    func testDatesAndTimesSortInSpreadsheets() throws {
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 3, hour: 14, minute: 5)))
        let formats = CSVDateFormats(timeZone: utc)
        XCTAssertEqual(formats.day(date), "2026-09-03")
        XCTAssertEqual(formats.time(date), "14:05")
        XCTAssertEqual(formats.month(date), "2026-09")
        XCTAssertEqual(formats.stamp(date), "2026-09-03 14:05")
        XCTAssertEqual(formats.day(nil), "")
    }
}
