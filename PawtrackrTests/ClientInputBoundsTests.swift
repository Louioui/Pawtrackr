import XCTest

@testable import Pawtrackr

final class ClientInputBoundsTests: XCTestCase {
    func testEditClientSheetLimitsVisibleFreeTextFields() throws {
        let source = try loadSource("Pawtrackr/Features/Clients/EditClientSheet.swift")

        XCTAssertTrue(
            source.contains(".textLengthLimit($firstName, to: TextInputLimits.name)"),
            "First-name edits must clamp pasted text before layouts render it."
        )
        XCTAssertTrue(
            source.contains(".textLengthLimit($lastName, to: TextInputLimits.name)"),
            "Last-name edits must clamp pasted text before layouts render it."
        )
        XCTAssertTrue(
            source.contains(".textLengthLimit($phone, to: TextInputLimits.phone)"),
            "Phone edits must clamp pasted text before formatting and persistence."
        )
        XCTAssertTrue(
            source.contains(".textLengthLimit($email, to: TextInputLimits.email)"),
            "Email edits must clamp pasted text before layouts render it."
        )
        XCTAssertTrue(
            source.contains(".textLengthLimit($address, to: TextInputLimits.address)"),
            "Address edits must clamp pasted text before layouts render it."
        )
    }

    func testClientDetailInlineAndEmergencyContactEditorsLimitVisibleFreeTextFields() throws {
        let source = try loadSource("Pawtrackr/Features/Clients/ClientDetailView.swift")

        XCTAssertTrue(
            source.contains(".textLengthLimit($newContactName, to: TextInputLimits.name)"),
            "Emergency-contact names must clamp pasted text."
        )
        XCTAssertTrue(
            source.contains(".textLengthLimit($newContactRelation, to: TextInputLimits.shortText)"),
            "Emergency-contact relations must clamp pasted text."
        )
        XCTAssertTrue(
            source.contains(".textLengthLimit($newContactPhone, to: TextInputLimits.phone)"),
            "Emergency-contact phones must clamp pasted text before formatting."
        )
        XCTAssertTrue(
            source.contains(".textLengthLimit($editFirst, to: TextInputLimits.name)"),
            "Inline first-name edits must clamp pasted text."
        )
        XCTAssertTrue(
            source.contains(".textLengthLimit($editLast, to: TextInputLimits.name)"),
            "Inline last-name edits must clamp pasted text."
        )
        XCTAssertTrue(
            source.contains(".textLengthLimit($editPhone, to: TextInputLimits.phone)"),
            "Inline phone edits must clamp pasted text before formatting."
        )
        XCTAssertTrue(
            source.contains(".textLengthLimit($editEmail, to: TextInputLimits.email)"),
            "Inline email edits must clamp pasted text."
        )
    }

    func testClientModelClampsOversizedFreeTextBeforePersisting() {
        let longName = String(repeating: "Name", count: 40)
        let longPhone = String(repeating: "5", count: 80)
        let longEmail = String(repeating: "customer", count: 40) + "@example.com"
        let longAddress = String(repeating: "123 Very Long Street ", count: 30)
        let longNotes = String(repeating: "Sensitive behavior note. ", count: 80)

        let client = Client(firstName: longName, lastName: longName, phone: longPhone, email: longEmail)
        client.setFirstName(longName)
        client.setLastName(longName)
        client.setPhone(longPhone)
        client.setEmail(longEmail)
        client.setAddress(longAddress)
        client.setNotes(longNotes)

        XCTAssertLessThanOrEqual(client.firstName.count, TextInputLimits.name)
        XCTAssertLessThanOrEqual(client.lastName.count, TextInputLimits.name)
        XCTAssertLessThanOrEqual(client.phone?.count ?? 0, TextInputLimits.phone)
        XCTAssertLessThanOrEqual(client.email?.count ?? 0, TextInputLimits.email)
        XCTAssertLessThanOrEqual(client.address?.count ?? 0, TextInputLimits.address)
        XCTAssertLessThanOrEqual(client.notes?.count ?? 0, TextInputLimits.notes)
    }

    func testEmergencyContactClampsOversizedFreeTextBeforePersisting() {
        let longName = String(repeating: "Contact", count: 20)
        let longRelation = String(repeating: "Family friend ", count: 20)
        let longPhone = String(repeating: "5", count: 80)

        let contact = EmergencyContact(name: longName, relation: longRelation, phone: longPhone)

        XCTAssertLessThanOrEqual(contact.name.count, TextInputLimits.name)
        XCTAssertLessThanOrEqual(contact.relation?.count ?? 0, TextInputLimits.shortText)
        XCTAssertLessThanOrEqual(contact.phone.count, TextInputLimits.phone)
    }

    private func loadSource(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
