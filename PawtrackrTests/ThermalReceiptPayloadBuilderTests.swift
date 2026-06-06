import XCTest
@testable import Pawtrackr

final class ThermalReceiptPayloadBuilderTests: XCTestCase {
    func testPayloadIncludesEscPosFramingAndReceiptText() throws {
        let payload = ThermalReceiptPayloadBuilder.payload(for: makeSnapshot())
        let text = try XCTUnwrap(String(data: payload, encoding: .ascii))

        XCTAssertTrue(payload.starts(with: Data([0x1B, 0x40])))
        XCTAssertTrue(text.contains("PAWTRACKR SALON"))
        XCTAssertTrue(text.contains("RECEIPT: #ABC12345"))
        XCTAssertTrue(text.contains("Bath"))
        XCTAssertTrue(text.contains("$45.00"))
        XCTAssertTrue(payload.suffix(4).elementsEqual(Data([0x1D, 0x56, 0x41, 0x10])))
        XCTAssertNil(payload.range(of: Data([0x1B, 0x70, 0x00, 0x19, 0xFA])))
    }

    func testCashReceiptCanPulseDrawerBeforeCut() {
        let payload = ThermalReceiptPayloadBuilder.payload(for: makeSnapshot(), opensCashDrawer: true)

        XCTAssertNotNil(payload.range(of: Data([0x1B, 0x70, 0x00, 0x19, 0xFA])))
        XCTAssertTrue(payload.suffix(4).elementsEqual(Data([0x1D, 0x56, 0x41, 0x10])))
    }

    private func makeSnapshot() -> ReceiptSnapshot {
        ReceiptSnapshot(
            businessName: "Pawtrackr Salon",
            businessAddress: "100 Main St",
            contactLine: "hello@example.com | 555-0100",
            receiptNumber: "RECEIPT: #ABC12345",
            clientName: "Jane Doe",
            clientPhoneFormatted: "(555) 123-4567",
            petLine: "Pet: Buddy (Poodle)",
            dateLine: "Date: Jan 1, 2026 at 10:00 AM",
            items: [
                .init(name: "Bath", priceString: "$30.00"),
                .init(name: "Nail Trim", priceString: "$15.00")
            ],
            totalString: "$45.00",
            payment: .init(infoLine: "Paid via Cash on Jan 1, 2026", referenceLine: nil)
        )
    }
}
