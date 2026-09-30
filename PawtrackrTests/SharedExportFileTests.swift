import XCTest
@testable import Pawtrackr

/// Exports are shared as named files (`SharedExportFile`), which AirDrop,
/// Mail, Messages and Files need.
final class SharedExportFileTests: XCTestCase {
    func testTheCopyHasTheExportsNameAndBytes() throws {
        let data = Data("Name\r\nJosé\r\n".utf8)
        let url = try SharedExportFile.write(data, named: "Pawtrackr_Clients_2026-09-30.csv")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        XCTAssertEqual(url.lastPathComponent, "Pawtrackr_Clients_2026-09-30.csv")
        XCTAssertEqual(try Data(contentsOf: url), data)
    }

    func testEachShareGetsItsOwnFolder() throws {
        let first = try SharedExportFile.write(Data("a".utf8), named: "Receipt.pdf")
        let second = try SharedExportFile.write(Data("b".utf8), named: "Receipt.pdf")
        defer {
            try? FileManager.default.removeItem(at: first.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: second.deletingLastPathComponent())
        }
        XCTAssertNotEqual(first, second, "Two receipts for pets with the same name don't overwrite each other.")
        XCTAssertEqual(try Data(contentsOf: first), Data("a".utf8))
    }

    func testNamesFromPetsAndSalonsAreSafeFileNames() {
        XCTAssertEqual(SharedExportFile.safeName("Receipt_Milo/Max.pdf"), "Receipt_Milo-Max.pdf")
        XCTAssertEqual(SharedExportFile.safeName("Report: Sept.pdf"), "Report- Sept.pdf")
        XCTAssertEqual(SharedExportFile.safeName("  "), "Pawtrackr")
    }
}
