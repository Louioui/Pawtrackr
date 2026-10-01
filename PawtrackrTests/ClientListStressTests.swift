//
//  ClientListStressTests.swift
//  PawtrackrTests
//
//  Floods an in-memory store with 500+ edge-case clients (ClientStressDataset)
//  and holds the client list to three reported bugs:
//  - Phantom duplicates: a client must never show twice, across sections or
//    within one, however fast clients are inserted, edited and deleted, and a
//    double tap on Create saves one client.
//  - Sorting: every sort is case- and accent-aware, puts clients without a
//    value last, and is a total order, so rows keep their places on refresh.
//  - Search: typing a name as the card shows it ("Zamora Ana") finds it, and
//    accents, case, field prefixes and stray colons behave.
//

import XCTest
import SwiftData
@testable import Pawtrackr

@MainActor
final class ClientListStressTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

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

    // MARK: - Helpers

    private func makeViewModel() async -> ClientsViewModel {
        let viewModel = ClientsViewModel(modelContext: context)
        await viewModel.waitForPendingFetch()
        return viewModel
    }

    private func storedClientIDs() throws -> Set<PersistentIdentifier> {
        Set(try context.fetch(FetchDescriptor<Client>()).map(\.persistentModelID))
    }

    private func listedIDs(_ viewModel: ClientsViewModel) -> [PersistentIdentifier] {
        (viewModel.inProgressClients + viewModel.otherClients).map(\.persistentModelID)
    }

    private func assertListedOnce(_ viewModel: ClientsViewModel, file: StaticString = #filePath, line: UInt = #line) {
        let ids = listedIDs(viewModel)
        XCTAssertEqual(Set(ids).count, ids.count, "A client is listed twice.", file: file, line: line)
    }

    private func search(_ viewModel: ClientsViewModel, _ text: String) async -> [Client] {
        viewModel.searchText = text
        viewModel.fetchClients() // skip the 300 ms typing debounce
        await viewModel.waitForPendingFetch()
        return viewModel.inProgressClients + viewModel.otherClients
    }

    /// The name a sort leads with, as the card shows it.
    private func leadingName(_ client: Client, lastNameFirst: Bool) -> String {
        let first = client.firstName.trimmed
        let last = client.lastName.trimmed
        if lastNameFirst { return last.isEmpty ? first : last }
        return first.isEmpty ? last : first
    }

    /// Adjacent rows never step backwards on the leading name, compared the
    /// way people read (case-insensitive, numbers in numeric order), and
    /// clients with no name at all come after every named one.
    private func assertNameOrder(_ clients: [Client], lastNameFirst: Bool, file: StaticString = #filePath, line: UInt = #line) {
        let keys = clients.map { leadingName($0, lastNameFirst: lastNameFirst) }
        if let firstNameless = keys.firstIndex(of: "") {
            XCTAssertTrue(keys[firstNameless...].allSatisfy(\.isEmpty), "A nameless client sorted before a named one.", file: file, line: line)
        }
        let named = keys.filter { !$0.isEmpty }
        for (previous, next) in zip(named, named.dropFirst()) {
            XCTAssertNotEqual(previous.localizedStandardCompare(next), .orderedDescending,
                              "\"\(previous)\" sorted before \"\(next)\".", file: file, line: line)
        }
    }

    // MARK: - Dataset

    func testDatasetHoldsFiveHundredPlusEdgeCaseClients() throws {
        let clients = try ClientStressDataset.seed(into: context)

        XCTAssertGreaterThanOrEqual(clients.count, 500)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Client>()), clients.count)
        XCTAssertTrue(clients.allSatisfy { $0.firstName.count <= TextInputLimits.name && $0.lastName.count <= TextInputLimits.name },
                      "Over-long names must be clamped on the way in.")
        XCTAssertTrue(clients.allSatisfy { $0.firstName == $0.firstName.trimmed && $0.lastName == $0.lastName.trimmed },
                      "Padding must be trimmed on the way in.")
        XCTAssertTrue(clients.contains { $0.firstName.isEmpty && !$0.lastName.isEmpty })
        XCTAssertTrue(clients.contains { $0.lastName.isEmpty && !$0.firstName.isEmpty })
    }

    // MARK: - Phantom duplicates

    func testWholeBookListsEveryClientExactlyOnce() async throws {
        let clients = try ClientStressDataset.seed(into: context)
        let checkedIn = try ClientStressDataset.checkIn(5, from: clients, in: context)

        let viewModel = await makeViewModel()

        XCTAssertEqual(Set(viewModel.inProgressClients.map(\.persistentModelID)), Set(checkedIn.map(\.persistentModelID)))
        assertListedOnce(viewModel)
        XCTAssertEqual(Set(listedIDs(viewModel)), try storedClientIDs())
    }

    /// The two sections come from separate store reads. If a visit starts or
    /// ends between them, one client can come back in both. The list keeps
    /// the in-progress card and drops the copy.
    func testClientReturnedInBothSectionsIsListedOnce() throws {
        let clients = try ClientStressDataset.seed(into: context)
        let shared = clients[10]

        let unique = ClientsViewModel.removingDuplicates(
            inProgress: [shared, shared],
            others: [clients[0], shared, clients[1], clients[0]]
        )

        XCTAssertEqual(unique.inProgress.map(\.persistentModelID), [shared.persistentModelID])
        XCTAssertEqual(unique.others.map(\.persistentModelID), [clients[0], clients[1]].map(\.persistentModelID))
    }

    /// Rapid inserts, edits, deletes and check-ins, each followed by a list
    /// refresh that the next change cancels mid-flight. Once things settle,
    /// the list must match the store exactly: nobody twice, nobody missing,
    /// still sorted.
    func testRapidChurnSettlesToTheStoreWithoutDuplicates() async throws {
        var clients = try ClientStressDataset.seed(into: context)
        let viewModel = await makeViewModel()
        var rng = ClientStressDataset.Generator(state: 0xC4_0A5)

        for step in 0..<300 {
            switch rng.nextInt(5) {
            case 0, 1:
                let client = Client(firstName: "Churn \(step)", lastName: rng.nextBool() ? "aardvark" : "Zed \(step)")
                context.insert(client)
                clients.append(client)
            case 2 where clients.count > 400:
                let victim = clients.remove(at: rng.nextInt(clients.count))
                context.delete(victim)
            case 3:
                let target = clients[rng.nextInt(clients.count)]
                target.setLastName(rng.nextBool() ? "älvarez \(step)" : "ALVAREZ \(step)")
            default:
                let owner = clients[rng.nextInt(clients.count)]
                if let pet = owner.pets?.first, !pet.isCheckedIn {
                    context.insert(Visit(pet: pet))
                } else {
                    let pet = Pet(name: "Churn pet \(step)", species: .dog)
                    pet.owner = owner
                    context.insert(pet)
                }
            }
            try context.save()
            viewModel.fetchClients()
            if step % 25 == 0 {
                // Let some refreshes land mid-churn as well.
                await viewModel.waitForPendingFetch()
                assertListedOnce(viewModel)
            }
        }

        viewModel.fetchClients()
        await viewModel.waitForPendingFetch()

        assertListedOnce(viewModel)
        XCTAssertEqual(Set(listedIDs(viewModel)), try storedClientIDs())
        assertNameOrder(viewModel.otherClients, lastNameFirst: true)
    }

    /// `isSaving` clears before the sheet finishes closing, which used to let
    /// a second tap on Create save the same client again.
    func testCreateTappedTwiceSavesOneClient() async throws {
        let viewModel = NewClientViewModel(modelContext: context)
        viewModel.first = "Double"
        viewModel.last = "Tap"
        // No phone, so the duplicate-phone check can't catch the second save.

        let first = await viewModel.createClient()
        let second = await viewModel.createClient()

        XCTAssertEqual(first, .created)
        XCTAssertEqual(second, .created)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Client>()).filter { $0.lastName == "Tap" }.count, 1)
    }

    func testOverlappingCreatesFromTwoFormsBothListOnce() async throws {
        try ClientStressDataset.seed(into: context)
        let list = await makeViewModel()

        let formA = NewClientViewModel(modelContext: context)
        formA.first = "Twin"; formA.last = "Alpha"
        let formB = NewClientViewModel(modelContext: context)
        formB.first = "Twin"; formB.last = "Beta"

        // Both saves are in flight before either finishes.
        let taskA = Task { await formA.createClient() }
        let taskB = Task { await formB.createClient() }
        let outcomes = [await taskA.value, await taskB.value]
        XCTAssertEqual(outcomes, [.created, .created])

        // .clientDidCreate refreshes the list on the next run loop pass.
        list.fetchClients()
        await list.waitForPendingFetch()

        assertListedOnce(list)
        XCTAssertEqual(list.otherClients.filter { $0.firstName == "Twin" }.count, 2)
        XCTAssertEqual(Set(listedIDs(list)), try storedClientIDs())
    }

    // MARK: - Sorting

    func testNameSortsAreCaseInsensitiveAndPutNamelessClientsLast() async throws {
        try ClientStressDataset.seed(into: context)
        let viewModel = await makeViewModel()

        viewModel.sortOption = .lastName
        await viewModel.waitForPendingFetch()
        assertNameOrder(viewModel.otherClients, lastNameFirst: true)

        let smithRows = viewModel.otherClients.enumerated()
            .filter { $0.element.lastName.lowercased() == "smith" }
            .map(\.offset)
        XCTAssertEqual(smithRows.count, 3)
        XCTAssertEqual(try XCTUnwrap(smithRows.last) - XCTUnwrap(smithRows.first), 2, "Smith, SMITH and smith must sit together.")

        let lastNames = viewModel.otherClients.map(\.lastName)
        let nine = try XCTUnwrap(lastNames.firstIndex(of: "Client 9"))
        let ten = try XCTUnwrap(lastNames.firstIndex(of: "Client 10"))
        XCTAssertLessThan(nine, ten, "Numbers in names sort numerically.")

        viewModel.sortOption = .firstName
        await viewModel.waitForPendingFetch()
        assertNameOrder(viewModel.otherClients, lastNameFirst: false)
    }

    /// Never-visited clients (and clients tied on a date) used to keep the
    /// store's byte order, which puts "Zed" before "adams" and "Émile" after
    /// "Zoe". They now fall back to the name.
    func testDateSortsBreakTiesByNameAndPutNeverVisitedLast() async throws {
        try ClientStressDataset.seed(into: context)
        let viewModel = await makeViewModel()

        viewModel.sortOption = .lastVisit
        await viewModel.waitForPendingFetch()
        let byVisit = viewModel.otherClients
        let dates = byVisit.map(\.lastVisitDate)
        if let firstNever = dates.firstIndex(where: { $0 == nil }) {
            XCTAssertTrue(dates[firstNever...].allSatisfy { $0 == nil }, "Never-visited clients go last.")
            assertNameOrder(Array(byVisit[firstNever...]), lastNameFirst: true)
        }
        for (previous, next) in zip(byVisit, byVisit.dropFirst()) {
            guard let p = previous.lastVisitDate, let n = next.lastVisitDate else { continue }
            XCTAssertGreaterThanOrEqual(p, n, "Most recent visit first.")
        }
        for group in Dictionary(grouping: byVisit.filter { $0.lastVisitDate != nil }, by: { $0.lastVisitDate! }).values where group.count > 1 {
            let rows = byVisit.filter { client in group.contains { $0 === client } }
            assertNameOrder(rows, lastNameFirst: true)
        }

        viewModel.sortOption = .newest
        await viewModel.waitForPendingFetch()
        let byNewest = viewModel.otherClients
        for (previous, next) in zip(byNewest, byNewest.dropFirst()) {
            XCTAssertGreaterThanOrEqual(previous.createdAt, next.createdAt)
        }
        for group in Dictionary(grouping: byNewest, by: \.createdAt).values where group.count > 1 {
            let rows = byNewest.filter { client in group.contains { $0 === client } }
            assertNameOrder(rows, lastNameFirst: true)
        }
    }

    func testPetSortUsesTheFirstPetTheCardShowsAndPutsPetlessClientsLast() async throws {
        try ClientStressDataset.seed(into: context)
        let viewModel = await makeViewModel()
        viewModel.sortOption = .petName
        await viewModel.waitForPendingFetch()

        func firstPet(_ client: Client) -> String? {
            (client.pets ?? []).map { $0.name.trimmed }.filter { !$0.isEmpty }
                .min { $0.localizedStandardCompare($1) == .orderedAscending }
        }

        let pets = viewModel.otherClients.map(firstPet)
        if let firstPetless = pets.firstIndex(where: { $0 == nil }) {
            XCTAssertTrue(pets[firstPetless...].allSatisfy { $0 == nil }, "Clients without pets go last.")
        }
        let named = pets.compactMap { $0 }
        for (previous, next) in zip(named, named.dropFirst()) {
            XCTAssertNotEqual(previous.localizedStandardCompare(next), .orderedDescending)
        }

        let owner = try XCTUnwrap(viewModel.otherClients.first { $0.lastName == ClientStressDataset.Landmark.twoPetOwner.1 })
        XCTAssertEqual(firstPet(owner), "apollo")
    }

    /// The same data must come back in the same order on every refresh, for
    /// every sort, including the three identical "Sam Lee" clients.
    func testEverySortIsStableAcrossRefreshes() async throws {
        try ClientStressDataset.seed(into: context)
        let viewModel = await makeViewModel()

        for option in ClientsViewModel.SortOption.allCases {
            viewModel.sortOption = option
            await viewModel.waitForPendingFetch()
            let first = viewModel.otherClients.map(\.persistentModelID)

            for _ in 0..<3 {
                viewModel.fetchClients()
                await viewModel.waitForPendingFetch()
                XCTAssertEqual(viewModel.otherClients.map(\.persistentModelID), first, "\(option) reordered rows on refresh.")
            }

            // A fresh list (a new repository and context read) agrees too.
            let fresh = ClientsViewModel(modelContext: context)
            fresh.sortOption = option
            await fresh.waitForPendingFetch()
            XCTAssertEqual(fresh.otherClients.map(\.persistentModelID), first, "\(option) differs between two lists.")
        }

        XCTAssertEqual(
            ClientsViewModel.sortClients(viewModel.otherClients.shuffled(), by: .lastName).map(\.persistentModelID),
            ClientsViewModel.sortClients(viewModel.otherClients, by: .lastName).map(\.persistentModelID),
            "Input order must not decide ties."
        )
    }

    // MARK: - Search

    func testSearchHandlesAccentsCaseScriptsAndPrefixes() async throws {
        try ClientStressDataset.seed(into: context)
        let viewModel = await makeViewModel()
        let everyone = try storedClientIDs()

        let nunez = await search(viewModel, "nunez")
        XCTAssertEqual(nunez.map(\.lastName), ["Ñúñez"], "Accents are ignored.")

        let smiths = await search(viewModel, "SMITH")
        XCTAssertEqual(Set(smiths.filter { $0.lastName.lowercased() == "smith" }.map(\.lastName)), Set(ClientStressDataset.Landmark.smithVariants))
        XCTAssertTrue(smiths.allSatisfy { $0.fullName.lowercased().contains("smith") })

        let wang = await search(viewModel, "王")
        XCTAssertTrue(wang.contains { $0.firstName == ClientStressDataset.Landmark.chinese.0 })

        let obrien = await search(viewModel, "n:o'brien")
        XCTAssertEqual(obrien.map(\.lastName), ["O'Brien"])

        let byPet = await search(viewModel, "pet:apollo")
        XCTAssertTrue(byPet.contains { $0.lastName == ClientStressDataset.Landmark.twoPetOwner.1 })
        XCTAssertTrue(byPet.allSatisfy { ($0.pets ?? []).contains { $0.name.lowercased().contains("apollo") } })

        let byPhone = await search(viewModel, "p:\(ClientStressDataset.Landmark.phoneDigits)")
        XCTAssertEqual(byPhone.map(\.lastName), ["Tone"])

        let samLees = await search(viewModel, "sam lee")
        XCTAssertEqual(samLees.count, 3)
        XCTAssertEqual(Set(samLees.map(\.persistentModelID)).count, 3)

        let blank = await search(viewModel, "   ")
        XCTAssertEqual(Set(blank.map(\.persistentModelID)), everyone, "A blank search shows everyone.")

        let none = await search(viewModel, "zzqx-no-such-client")
        XCTAssertTrue(none.isEmpty)

        viewModel.searchText = ""
        viewModel.fetchClients()
        await viewModel.waitForPendingFetch()
        XCTAssertEqual(Set(listedIDs(viewModel)), everyone)
    }

    /// Sorted by last name the card reads "Zamora Ana". Typing that used to
    /// find nobody, because only "Ana Zamora" matched the full name.
    func testSearchFindsANameTypedTheWayTheCardShowsIt() async throws {
        try ClientStressDataset.seed(into: context)
        let viewModel = await makeViewModel()
        let (first, last) = ClientStressDataset.Landmark.anaZamora

        let asShown = await search(viewModel, "\(last) \(first)")
        XCTAssertEqual(asShown.map(\.fullName), ["Ana Zamora"])

        let natural = await search(viewModel, "\(first) \(last)")
        XCTAssertEqual(natural.map(\.fullName), ["Ana Zamora"])

        let lowercase = await search(viewModel, "zamora ana")
        XCTAssertEqual(lowercase.map(\.fullName), ["Ana Zamora"])
    }

    /// A colon that isn't a known field prefix ("10:30", "note: ...") used to
    /// match nobody. It is plain text now.
    func testColonWithoutAKnownPrefixIsPlainText() async throws {
        let client = Client(firstName: "Ratio", lastName: "10:30")
        context.insert(client)
        try ClientStressDataset.seed(into: context)
        let viewModel = await makeViewModel()

        let hits = await search(viewModel, "10:30")
        XCTAssertTrue(hits.contains { $0.persistentModelID == client.persistentModelID })
    }

    func testSearchResultsAreSortedAndUniqueUnderEverySort() async throws {
        let clients = try ClientStressDataset.seed(into: context)
        _ = try ClientStressDataset.checkIn(5, from: clients, in: context)
        let viewModel = await makeViewModel()

        for query in ["a", "Adams", "é", "Client", "bella", "o'"] {
            for option in [ClientsViewModel.SortOption.lastName, .firstName] {
                viewModel.sortOption = option
                _ = await search(viewModel, query)
                assertListedOnce(viewModel)
                assertNameOrder(viewModel.otherClients, lastNameFirst: option == .lastName)
            }
        }
    }
}
