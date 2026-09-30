//
//  ClientsViewModelListTests.swift
//  PawtrackrTests
//
//  Regression: 72012e6 cut the client list's first fetch to a 100-row
//  last-name page. Smart filters and non-alphabetical sorts then ran on that
//  window only (a filter with no match in the first 100 showed "none", a new
//  "Zamora" never reached the top of Newest), and Load More repeated rows when
//  an in-progress client fell inside the first window. The list loads the
//  whole book again; these tests hold it there.
//

import XCTest
import SwiftData
@testable import Pawtrackr

@MainActor
final class ClientsViewModelListTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    /// More than the old 100-row page, so anything past row 100 by last name
    /// would have been invisible.
    private let bookSize = 150

    override func setUpWithError() throws {
        try super.setUpWithError()
        let schema = Schema(PawtrackrSchema.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [config])
        context = container.mainContext
    }

    override func tearDownWithError() throws {
        container = nil
        context = nil
        try super.tearDownWithError()
    }

    /// Complete clients "Aaron000"... (phone, email and an emergency
    /// contact) sorting before any "Z" surname, all created well in the past.
    @discardableResult
    private func seedBook() throws -> [Client] {
        var clients: [Client] = []
        for index in 0..<bookSize {
            let client = Client(
                firstName: "First\(index)",
                lastName: String(format: "Aaron%03d", index),
                phone: String(format: "+1555000%04d", index),
                email: "client\(index)@example.com"
            )
            client.createdAt = Date(timeIntervalSince1970: 1_700_000_000 + Double(index))
            context.insert(client)
            let contact = EmergencyContact(name: "Contact \(index)", phone: String(format: "+1555111%04d", index))
            contact.owner = client
            context.insert(contact)
            clients.append(client)
        }
        try context.save()
        return clients
    }

    private func makeViewModel() async -> ClientsViewModel {
        let viewModel = ClientsViewModel(modelContext: context)
        await viewModel.waitForPendingFetch()
        return viewModel
    }

    func testWholeBookLoadsWithoutPaging() async throws {
        try seedBook()

        let viewModel = await makeViewModel()

        XCTAssertEqual(viewModel.otherClients.count, bookSize)
        XCTAssertFalse(viewModel.canLoadMore, "The list is one bounded fetch; there is no page to load.")
    }

    func testMissingInfoFilterFindsAClientPastTheFirstHundred() async throws {
        try seedBook()
        let late = Client(firstName: "Zoe", lastName: "Zimmerman", phone: "+15559990000", email: nil)
        context.insert(late)
        try context.save()

        let viewModel = await makeViewModel()
        viewModel.selectedFilter = .missingInfo
        await viewModel.waitForPendingFetch()

        XCTAssertEqual(viewModel.otherClients.map(\.lastName), ["Zimmerman"],
                       "A filter match past row 100 by last name must still show.")
    }

    /// The profile says "Missing: Emergency contact" for a client with a
    /// phone and an email but nobody to call. The filter lists them too.
    func testMissingInfoFilterListsAClientWithoutAnEmergencyContact() async throws {
        try seedBook()
        let noBackup = Client(firstName: "Alien", lastName: "Cullen", phone: "+14453453443", email: "l@gamil.com")
        let blankEmail = Client(firstName: "Bo", lastName: "Blank", phone: "+15559990002", email: "   ")
        for client in [noBackup, blankEmail] {
            context.insert(client)
        }
        let contact = EmergencyContact(name: "Rosa", phone: "+15559990003")
        contact.owner = blankEmail
        context.insert(contact)
        try context.save()

        let viewModel = await makeViewModel()
        viewModel.selectedFilter = .missingInfo
        await viewModel.waitForPendingFetch()

        XCTAssertEqual(Set(viewModel.otherClients.map(\.lastName)), ["Cullen", "Blank"], "Blank text counts as missing too.")
        XCTAssertEqual(ClientMissingInfo.items(for: noBackup), [.emergencyContact])
    }

    func testNewestSortPutsALateSurnameFirst() async throws {
        try seedBook()
        let newest = Client(firstName: "Ana", lastName: "Zamora", phone: "+15559990001", email: "ana@example.com")
        newest.createdAt = Date()
        context.insert(newest)
        try context.save()

        let viewModel = await makeViewModel()
        viewModel.sortOption = .newest
        await viewModel.waitForPendingFetch()

        XCTAssertEqual(viewModel.otherClients.first?.lastName, "Zamora")
        XCTAssertEqual(viewModel.otherClients.count, bookSize + 1)
    }

    func testCheckedInClientAppearsOnceAndIsNotRepeated() async throws {
        let clients = try seedBook()
        let checkedIn = clients[1]
        let pet = Pet(name: "Milo", species: .dog)
        pet.owner = checkedIn
        context.insert(pet)
        let visit = Visit(pet: pet)
        context.insert(visit)
        try context.save()

        let viewModel = await makeViewModel()

        let inProgressIDs = viewModel.inProgressClients.map(\.persistentModelID)
        let otherIDs = viewModel.otherClients.map(\.persistentModelID)
        XCTAssertEqual(inProgressIDs, [checkedIn.persistentModelID])
        XCTAssertFalse(otherIDs.contains(checkedIn.persistentModelID))
        XCTAssertEqual(Set(otherIDs).count, otherIDs.count, "No client may be listed twice.")
        XCTAssertEqual(inProgressIDs.count + otherIDs.count, bookSize)

        // Load More must be a no-op: there is no second page to append.
        viewModel.loadMore()
        await viewModel.waitForPendingFetch()
        XCTAssertEqual(viewModel.otherClients.map(\.persistentModelID), otherIDs)
    }
}
