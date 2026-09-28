import XCTest
import SwiftData
@testable import Pawtrackr

/// Emergency contacts typed into New Client, or into the contact editor on
/// Client Details, must never vanish on save.
///
/// Before the fix, `NewClientViewModel` kept a contact only when its phone
/// parsed as a US number. A name-only contact, or one with a local, short or
/// international number, was dropped without a word, the client saved, and
/// Client Details said "No emergency contacts yet".
@MainActor
final class EmergencyContactCaptureTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema(PawtrackrSchema.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [config])
        context = container.mainContext
    }

    override func tearDownWithError() throws {
        container = nil
        context = nil
    }

    private func makeViewModel() -> NewClientViewModel {
        let vm = NewClientViewModel(modelContext: context)
        vm.first = "Ava"
        vm.last = "Stone"
        return vm
    }

    private func storedContacts() throws -> [EmergencyContact] {
        try context.fetch(FetchDescriptor<EmergencyContact>(sortBy: [SortDescriptor(\.name)]))
    }

    // MARK: - Rules

    func testRulesClassifyEveryRowShape() {
        XCTAssertEqual(EmergencyContactRules.evaluate(name: "  ", phone: " "), .blank)
        XCTAssertEqual(EmergencyContactRules.evaluate(name: "Riley", phone: ""), .valid(storedPhone: ""))
        XCTAssertEqual(EmergencyContactRules.evaluate(name: "Riley", phone: "(312) 555-0111"), .valid(storedPhone: "+13125550111"))
        XCTAssertEqual(
            EmergencyContactRules.evaluate(name: "Riley", phone: "555-1234"),
            .invalid(.phone, message: EmergencyContactRules.phoneInvalidMessage)
        )
        XCTAssertEqual(
            EmergencyContactRules.evaluate(name: "Riley", phone: "+44 20 7946 0958"),
            .invalid(.phone, message: EmergencyContactRules.phoneInvalidMessage)
        )
        XCTAssertEqual(
            EmergencyContactRules.evaluate(name: "", phone: "(312) 555-0111"),
            .invalid(.name, message: EmergencyContactRules.nameRequiredMessage)
        )
    }

    func testSummaryLineLeavesOutEmptyParts() {
        XCTAssertEqual(
            EmergencyContactRules.summaryLine(name: "Maria", relation: "sister", phone: "+13125550111"),
            "Maria (sister) · (312) 555-0111"
        )
        XCTAssertEqual(EmergencyContactRules.summaryLine(name: "Maria", relation: nil, phone: ""), "Maria")
        XCTAssertEqual(EmergencyContactRules.summaryLine(name: "Maria", relation: " ", phone: "5551234"), "Maria · 5551234")
    }

    // MARK: - New Client flow

    func testValidPhoneIsStoredAsE164() async throws {
        let vm = makeViewModel()
        vm.contacts[0].name = "casey backup"
        vm.contacts[0].phone = "(312) 555-0111"

        let outcome = await vm.createClient()

        XCTAssertEqual(outcome, .created)
        let contacts = try storedContacts()
        XCTAssertEqual(contacts.map(\.name), ["Casey Backup"])
        XCTAssertEqual(contacts.first?.phone, "+13125550111")
    }

    func testNameOnlyContactIsSavedInsteadOfDropped() async throws {
        let vm = makeViewModel()
        vm.contacts[0].name = "Riley Backup"

        let outcome = await vm.createClient()

        XCTAssertEqual(outcome, .created)
        let contacts = try storedContacts()
        XCTAssertEqual(contacts.map(\.name), ["Riley Backup"], "A contact with a name and no phone must be saved, not dropped.")
        XCTAssertEqual(contacts.first?.phone, "")
        XCTAssertEqual(contacts.first?.owner?.firstName, "Ava")
    }

    func testUnparseablePhoneBlocksSaveInsteadOfDroppingTheContact() async throws {
        let vm = makeViewModel()
        vm.contacts[0].name = "Jordan Backup"
        vm.contacts[0].phone = "555-1234"

        let outcome = await vm.createClient()

        XCTAssertEqual(outcome, .failed, "An emergency phone that can't be read must stop the save so the groomer can fix it.")
        XCTAssertTrue(try context.fetch(FetchDescriptor<Client>()).isEmpty, "Nothing may be saved while a contact is invalid.")
        XCTAssertTrue(try storedContacts().isEmpty)
        XCTAssertEqual(vm.contacts[0].name, "Jordan Backup", "What the groomer typed must still be in the form.")
        XCTAssertEqual(vm.contacts[0].phone, "555-1234")
        XCTAssertNotNil(vm.appError, "The groomer must be told why nothing saved.")
        XCTAssertEqual(
            vm.contactValidationError(for: vm.contacts[0].id, field: .phone),
            EmergencyContactRules.phoneInvalidMessage,
            "The message belongs on the phone field of that contact."
        )

        vm.contacts[0].phone = ""
        vm.clearContactValidationErrors(for: vm.contacts[0].id)
        XCTAssertNil(vm.contactValidationError(for: vm.contacts[0].id, field: .phone))
        let retry = await vm.createClient()
        XCTAssertEqual(retry, .created, "Clearing the phone lets the name-only contact save.")
        XCTAssertEqual(try storedContacts().map(\.name), ["Jordan Backup"])
    }

    func testPhoneWithoutNameBlocksSave() async throws {
        let vm = makeViewModel()
        vm.contacts[0].phone = "(312) 555-0111"

        let outcome = await vm.createClient()

        XCTAssertEqual(outcome, .failed)
        XCTAssertTrue(try context.fetch(FetchDescriptor<Client>()).isEmpty)
        XCTAssertEqual(
            vm.contactValidationError(for: vm.contacts[0].id, field: .name),
            EmergencyContactRules.nameRequiredMessage
        )
    }

    func testBlankRowsAreIgnoredAndOtherRowsAllSave() async throws {
        let vm = makeViewModel()
        vm.addContact()
        vm.addContact()
        vm.contacts[1].name = "Maria"
        vm.contacts[2].name = "Sam"
        vm.contacts[2].phone = "3125550199"

        let outcome = await vm.createClient()

        XCTAssertEqual(outcome, .created)
        let contacts = try storedContacts()
        XCTAssertEqual(contacts.map(\.name), ["Maria", "Sam"])
        XCTAssertEqual(contacts.map(\.phone), ["", "+13125550199"])
    }

    func testClientDetailShowsContactsSavedFromNewClient() async throws {
        let vm = makeViewModel()
        vm.addContact()
        vm.contacts[0].name = "Zed Neighbor"
        vm.contacts[1].name = "Ann Sister"
        vm.contacts[1].phone = "(312) 555-0111"
        let outcome = await vm.createClient()
        XCTAssertEqual(outcome, .created)

        let client = try XCTUnwrap(context.fetch(FetchDescriptor<Client>()).first)
        let detail = ClientDetailViewModel(client: client, modelContext: context)
        detail.refreshEmergencyContacts()

        XCTAssertEqual(detail.emergencyContacts.map(\.name), ["Ann Sister", "Zed Neighbor"])
        XCTAssertEqual(detail.primaryEmergencyContact?.name, "Ann Sister", "The header shows the first contact in the card's order.")
    }

    // MARK: - Contact editor on Client Details

    private func makeDetail() throws -> ClientDetailViewModel {
        let client = Client(firstName: "Ava", lastName: "Stone")
        context.insert(client)
        try context.save()
        return ClientDetailViewModel(client: client, modelContext: context)
    }

    func testEditorSavesNameOnlyContact() throws {
        let detail = try makeDetail()

        let result = detail.saveEmergencyContact(editing: nil, name: "Riley", relation: "friend", phone: "")

        XCTAssertEqual(result, .saved)
        XCTAssertEqual(detail.emergencyContacts.map(\.name), ["Riley"])
        XCTAssertEqual(detail.emergencyContacts.first?.phone, "")
        XCTAssertEqual(detail.emergencyContacts.first?.relation, "friend")
    }

    func testEditorBlocksUnreadablePhoneAndMissingName() throws {
        let detail = try makeDetail()

        XCTAssertEqual(
            detail.saveEmergencyContact(editing: nil, name: "Riley", relation: "", phone: "555-1234"),
            .invalid(.phone, message: EmergencyContactRules.phoneInvalidMessage)
        )
        XCTAssertEqual(
            detail.saveEmergencyContact(editing: nil, name: " ", relation: "", phone: ""),
            .invalid(.name, message: EmergencyContactRules.nameMissingMessage)
        )
        XCTAssertEqual(
            detail.saveEmergencyContact(editing: nil, name: "", relation: "", phone: "3125550111"),
            .invalid(.name, message: EmergencyContactRules.nameRequiredMessage)
        )
        XCTAssertTrue(try storedContacts().isEmpty)
    }

    func testEditorWritesNothingWhenNothingChanged() throws {
        let detail = try makeDetail()
        XCTAssertEqual(detail.saveEmergencyContact(editing: nil, name: "Riley", relation: "friend", phone: "3125550111"), .saved)
        let contact = try XCTUnwrap(detail.emergencyContacts.first)

        // The editor shows the stored phone formatted for reading.
        let result = detail.saveEmergencyContact(
            editing: contact,
            name: "Riley",
            relation: "friend",
            phone: PhoneUtils.display(contact.phone) ?? contact.phone
        )

        XCTAssertEqual(result, .unchanged)
        XCTAssertFalse(context.hasChanges, "An unchanged contact must not be assigned: every assignment uploads the row.")
    }

    func testEditorKeepsAnUntouchedOlderPhoneWhenOtherFieldsChange() throws {
        let detail = try makeDetail()
        let legacy = EmergencyContact(name: "Old Friend", relation: nil, phone: "555-1234")
        legacy.owner = detail.client
        context.insert(legacy)
        try context.save()

        let result = detail.saveEmergencyContact(editing: legacy, name: "Old Friend", relation: "neighbor", phone: "555-1234")

        XCTAssertEqual(result, .saved)
        XCTAssertEqual(legacy.phone, "555-1234", "A phone the groomer didn't touch stays as stored.")
        XCTAssertEqual(legacy.relation, "neighbor")
    }
}
