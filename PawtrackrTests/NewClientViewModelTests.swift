import XCTest
import SwiftData
@testable import Pawtrackr

/// Isolates `NewClientViewModel.createClient()` from the SwiftUI/macOS view layer.
/// If these pass, a "Create does nothing" report points at the View (button/toolbar/
/// dismiss), not the view-model logic.
@MainActor
final class NewClientViewModelTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema(PawtrackrSchema.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [config])
        context = container.mainContext
    }

    override func tearDownWithError() throws {
        container = nil; context = nil
    }

    func testCreateClient_validInput_returnsCreatedAndPersists() async throws {
        let vm = NewClientViewModel(modelContext: context)
        vm.first = "John"
        vm.last = "Doe"
        // Leave phone empty so the duplicate-lookup repository path is skipped.

        let outcome = await vm.createClient()

        XCTAssertEqual(outcome, .created)
        XCTAssertNil(vm.appError)
        XCTAssertFalse(vm.isSaving, "isSaving must reset so the Create button re-enables")

        let clients = try context.fetch(FetchDescriptor<Client>())
        XCTAssertEqual(clients.count, 1)
        XCTAssertEqual(clients.first?.firstName, "John")
        XCTAssertEqual(clients.first?.lastName, "Doe")
    }

    func testCreateClient_withPhone_createsWhenNoDuplicate() async throws {
        let vm = NewClientViewModel(modelContext: context)
        vm.first = "Jane"
        vm.last = "Smith"
        vm.phone = "2125551234" // valid NANP: area 212, exchange 555

        let outcome = await vm.createClient()

        XCTAssertEqual(outcome, .created, "Should create; the findClient duplicate path must not hang or false-positive")
        XCTAssertFalse(vm.isSaving)
    }

    func testCreateClient_emptyFirstName_failsWithError() async throws {
        let vm = NewClientViewModel(modelContext: context)
        vm.first = ""
        vm.last = "Doe"

        let outcome = await vm.createClient()

        XCTAssertEqual(outcome, .failed)
        XCTAssertNotNil(vm.appError, "A validation failure must surface an appError for the alert to show")
        XCTAssertFalse(vm.isSaving)
    }

    func testCreateClient_duplicatePhone_failsWithError() async throws {
        // Seed an existing client with a known E.164 phone.
        let existing = Client(firstName: "Existing", lastName: "Person", phone: "+12125551234")
        context.insert(existing)
        try context.save()

        let vm = NewClientViewModel(modelContext: context)
        vm.first = "New"
        vm.last = "Person"
        vm.phone = "2125551234" // normalizes to +12125551234

        let outcome = await vm.createClient()

        XCTAssertEqual(outcome, .duplicateFound)
        XCTAssertNotNil(vm.appError, "Duplicate must surface an appError so the user sees why nothing saved")
        XCTAssertFalse(vm.isSaving)
    }
}
