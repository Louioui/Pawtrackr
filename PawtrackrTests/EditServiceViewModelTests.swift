//
//  EditServiceViewModelTests.swift
//  PawtrackrTests
//
//  Covers the rules around saving services: validation, duplicate-name
//  detection on both create and rename, and rename-of-self being a
//  no-op (the bug class where editing an existing service to keep its
//  name unchanged would falsely match itself as a "duplicate").
//

import XCTest
import SwiftData
@testable import Pawtrackr

@MainActor
final class EditServiceViewModelTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var repo: ServiceRepository!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let schema = Schema(PawtrackrSchema.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [config])
        context = container.mainContext
        repo = ServiceRepository(modelContainer: container)
    }

    override func tearDownWithError() throws {
        container = nil
        context = nil
        repo = nil
        try super.tearDownWithError()
    }

    // MARK: - Validation

    func testSave_RejectsBlankName() async throws {
        let vm = EditServiceViewModel(modelContext: context, service: nil, repository: repo)
        vm.name = "   "
        vm.price = 50

        do {
            try await vm.save()
            XCTFail("Saving with blank name should throw.")
        } catch is ValidationError {
            // Expected
        }
    }

    func testSave_RejectsNegativePrice() async throws {
        let vm = EditServiceViewModel(modelContext: context, service: nil, repository: repo)
        vm.name = "Bath"
        vm.price = -10

        do {
            try await vm.save()
            XCTFail("Saving with negative price should throw.")
        } catch is ValidationError {
            // Expected
        }
    }

    func testSave_RejectsZeroDuration() async throws {
        let vm = EditServiceViewModel(modelContext: context, service: nil, repository: repo)
        vm.name = "Bath"
        vm.price = 50
        vm.duration = 0

        do {
            try await vm.save()
            XCTFail("Saving with zero duration should throw.")
        } catch is ValidationError {
            // Expected
        }
    }

    // MARK: - Duplicate-name rules

    func testSave_RejectsDuplicateNameOnCreate() async throws {
        try seedService(named: "Bath", price: 45)

        let vm = EditServiceViewModel(modelContext: context, service: nil, repository: repo)
        vm.name = "Bath"
        vm.price = 99

        do {
            try await vm.save()
            XCTFail("Should reject creating a service that duplicates an existing name.")
        } catch is ValidationError {
            // Expected
        }
    }

    func testSave_RejectsDuplicateNameOnCreate_CaseInsensitive() async throws {
        try seedService(named: "Bath", price: 45)

        let vm = EditServiceViewModel(modelContext: context, service: nil, repository: repo)
        vm.name = "bath"
        vm.price = 99

        do {
            try await vm.save()
            XCTFail("Duplicate name check must be case-insensitive.")
        } catch is ValidationError {
            // Expected
        }
    }

    /// Regression: renaming a service to its own name (i.e. unchanged name
    /// edits) used to fail because the duplicate check ran indiscriminately
    /// and matched the row against itself. After the fix, saving an
    /// unchanged-name edit should succeed.
    func testSave_AllowsEditingExistingServiceWithoutNameChange() async throws {
        let bath = try seedService(named: "Bath", price: 45)

        let vm = EditServiceViewModel(modelContext: context, service: bath, repository: repo)
        // name is already "Bath" via init copy
        vm.price = 55

        try await vm.save()

        let all = try await repo.fetchAllServices()
        XCTAssertEqual(all.count, 1, "No new service should have been created.")
        XCTAssertEqual(all.first?.basePrice, 55, "Price should have been updated.")
    }

    /// Regression: renaming a service to *another* service's name was
    /// allowed because the dupe check only ran on creation. The fix runs
    /// the dupe check whenever the name actually changes, while excluding
    /// the row being edited so no false self-match.
    func testSave_RejectsRenamingExistingServiceToAnothersName() async throws {
        _ = try seedService(named: "Haircut", price: 60)
        let bath = try seedService(named: "Bath", price: 45)

        let vm = EditServiceViewModel(modelContext: context, service: bath, repository: repo)
        vm.name = "Haircut"

        do {
            try await vm.save()
            XCTFail("Renaming to a name another service already uses should throw.")
        } catch is ValidationError {
            // Expected
        }

        // Original price/name should be untouched on the persistent row.
        let all = try await repo.fetchAllServices()
        let names = Set(all.map(\.name))
        XCTAssertEqual(names, ["Bath", "Haircut"], "Both original services should still exist with their original names.")
    }

    // MARK: - Helpers

    @discardableResult
    private func seedService(named name: String, price: Decimal) throws -> Service {
        let s = Service(name: name)
        s.setBasePrice(price)
        s.setEnabled(true)
        context.insert(s)
        try context.save()
        return s
    }
}
