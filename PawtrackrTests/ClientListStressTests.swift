//
//  ClientListStressTests.swift
//  PawtrackrTests
//
//  Floods an in-memory store with `ClientStressDataset` (600 hostile client
//  records) and holds the client list to three promises under that load and
//  under rapid insert / rename / delete churn from several contexts:
//
//  - every client is listed exactly once (the "phantom duplicate" report);
//  - the order is total and repeatable, ignoring case and accents, with
//    blank names last (the sorting report, and cards swapping places);
//  - search and the smart filters return exactly what they should.
//

import XCTest
import SwiftData
@testable import Pawtrackr

@MainActor
final class ClientListStressTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    private let bookSize = 600

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

    private func makeViewModel(repository: ClientRepositoryProtocol? = nil) async -> ClientsViewModel {
        let viewModel = ClientsViewModel(modelContext: context, repository: repository)
        await viewModel.waitForPendingFetch()
        return viewModel
    }

    private func refresh(_ viewModel: ClientsViewModel) async {
        viewModel.fetchClients()
        await viewModel.waitForPendingFetch()
    }

    private func search(_ viewModel: ClientsViewModel, _ text: String) async -> [Client] {
        viewModel.searchText = text
        // Skip the 300 ms debounce: fetchClients cancels it and fetches now.
        await refresh(viewModel)
        return viewModel.inProgressClients + viewModel.otherClients
    }

    private func listedIDs(_ viewModel: ClientsViewModel) -> [PersistentIdentifier] {
        (viewModel.inProgressClients + viewModel.otherClients).map(\.persistentModelID)
    }

    private func assertListedOnce(_ viewModel: ClientsViewModel, file: StaticString = #filePath, line: UInt = #line) {
        let ids = listedIDs(viewModel)
        XCTAssertEqual(Set(ids).count, ids.count, "A client is listed twice.", file: file, line: line)
    }

    private func storeCount() throws -> Int {
        try context.fetchCount(FetchDescriptor<Client>())
    }

    private func folded(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }

    @discardableResult
    private func makeClient(_ first: String, _ last: String, phone: String? = nil, pets: [String] = [], lastVisit: Date? = nil) -> Client {
        let client = Client(firstName: first, lastName: last)
        client.setPhone(phone)
        client.lastVisitDate = lastVisit
        context.insert(client)
        for name in pets {
            let pet = Pet(name: name, species: .dog)
            pet.owner = client
            context.insert(pet)
        }
        return client
    }

    // MARK: - The dataset itself

    func testStressBookIsLargeHostileAndReproducible() {
        let specs = ClientStressDataset.makeSpecs(count: bookSize)

        XCTAssertEqual(specs.count, bookSize)
        XCTAssertEqual(specs, ClientStressDataset.makeSpecs(count: bookSize), "The same seed must give the same book.")
        XCTAssertNotEqual(specs, ClientStressDataset.makeSpecs(count: bookSize, seed: 42))

        XCTAssertTrue(specs.contains { $0.firstName.isEmpty && $0.lastName.isEmpty }, "No nameless client")
        XCTAssertTrue(specs.contains { !$0.firstName.isEmpty && $0.firstName.trimmed.isEmpty }, "No whitespace-only name")
        XCTAssertTrue(specs.contains { $0.firstName.count > TextInputLimits.name && $0.bypassesSetters }, "No over-long imported name")
        XCTAssertTrue(specs.contains { $0.firstName.unicodeScalars.contains { $0.properties.isEmojiPresentation } }, "No emoji name")
        XCTAssertTrue(specs.contains { $0.firstName == "محمد" }, "No right-to-left name")
        XCTAssertTrue(specs.contains { $0.firstName == "Jose\u{301}" } && specs.contains { $0.firstName == "José" }, "No decomposed/precomposed pair")
        XCTAssertGreaterThan(specs.filter { $0.firstName == "Maria" && $0.lastName == "Lopez" }.count, 20, "Too few exact duplicate names")
        XCTAssertTrue(specs.contains { $0.phone == "abcdefg" }, "No garbage phone")
        XCTAssertTrue(specs.contains { $0.phone == "(312) 555-0123" }, "No formatted phone")
        XCTAssertTrue(specs.contains { $0.phone?.hasPrefix("+44") == true }, "No international phone")
        XCTAssertTrue(specs.contains { $0.phone == nil }, "No missing phone")
        XCTAssertEqual(specs.filter { $0.lastName == ClientStressDataset.sentinelLastName }.count, 1)
    }

    func testStressBookSeedsIntoTheStore() throws {
        let clients = try ClientStressDataset.seed(into: context, count: bookSize)

        XCTAssertEqual(clients.count, bookSize)
        XCTAssertEqual(try storeCount(), bookSize)
        XCTAssertEqual(Set(clients.map(\.uuid)).count, bookSize, "Every client needs its own UUID.")
        XCTAssertTrue(clients.contains { $0.firstName.count > TextInputLimits.name }, "Imported names keep their full length.")
    }

    // MARK: - Phantom duplicates

    func testWholeStressBookIsListedOnceInEverySortAndFilter() async throws {
        try ClientStressDataset.seed(into: context, count: bookSize)
        let viewModel = await makeViewModel()

        for option in ClientsViewModel.SortOption.allCases {
            viewModel.sortOption = option
            await viewModel.waitForPendingFetch()
            XCTAssertEqual(listedIDs(viewModel).count, bookSize, "\(option) lost or repeated clients")
            assertListedOnce(viewModel)
        }
        for filter in ClientsViewModel.Filter.allCases {
            viewModel.selectedFilter = filter
            await viewModel.waitForPendingFetch()
            assertListedOnce(viewModel)
        }
    }

    /// Whatever a repository answers, a client in both sections is listed
    /// once, in session, and a repeated row doesn't survive either.
    func testClientReturnedInBothSectionsIsListedOnceInSession() async throws {
        let inSession = makeClient("Ines", "Session")
        let waiting = makeClient("Walt", "Waiting")
        try context.save()

        let repository = MockClientRepository()
        repository.activeClients = [inSession.persistentModelID]
        repository.clients = [waiting.persistentModelID, inSession.persistentModelID, waiting.persistentModelID]

        let viewModel = await makeViewModel(repository: repository)

        XCTAssertEqual(viewModel.inProgressClients.map(\.persistentModelID), [inSession.persistentModelID])
        XCTAssertEqual(viewModel.otherClients.map(\.persistentModelID), [waiting.persistentModelID])
    }

    /// Inserts from several background contexts, renames and deletes on the
    /// main context, and list refreshes, all interleaved. Whatever order they
    /// land in, the settled list is the store: once each, in order.
    func testRapidInsertRenameDeleteChurnSettlesToTheStoreWithoutDuplicates() async throws {
        let seeded = try ClientStressDataset.seed(into: context, count: 200)
        let viewModel = await makeViewModel()
        let repositories = (0..<4).map { _ in ClientRepository(modelContainer: container) }
        var rng = SplitMix64(seed: 7)
        var deleted = Set<PersistentIdentifier>()

        for round in 0..<25 {
            // A burst of creates through the repository the New Client form uses.
            try await withThrowingTaskGroup(of: PersistentIdentifier.self) { group in
                for slot in 0..<8 {
                    let repository = repositories[slot % repositories.count]
                    let spec = ClientStressDataset.makeSpecs(count: 12, seed: UInt64(round * 100 + slot))[slot + 1]
                    group.addTask {
                        try await repository.createClient(
                            firstName: spec.firstName,
                            lastName: spec.lastName,
                            phone: spec.phone ?? "",
                            email: "",
                            address: "",
                            photoData: nil,
                            pets: [],
                            contacts: []
                        )
                    }
                }
                // The list refreshes while those saves are still landing.
                viewModel.fetchClients()
                try await group.waitForAll()
            }

            // Renames that move cards across the alphabet, and deletes.
            let alive = seeded.filter { !deleted.contains($0.persistentModelID) }
            for _ in 0..<5 {
                rng.pick(alive).setLastName(rng.pick(ClientStressDataset.edgeLastNames + ["Aardvark", "Zyzzyva"]))
            }
            let victim = rng.pick(alive)
            deleted.insert(victim.persistentModelID)
            if round.isMultiple(of: 2) {
                context.delete(victim)
                try context.save()
            } else {
                try context.save()
                try await repositories[round % repositories.count].deleteClient(id: victim.persistentModelID)
            }
            viewModel.fetchClients()
            if round.isMultiple(of: 3) { viewModel.sortOption = rng.pick(ClientsViewModel.SortOption.allCases) }
        }

        await refresh(viewModel)

        let ids = listedIDs(viewModel)
        assertListedOnce(viewModel)
        XCTAssertEqual(ids.count, try storeCount(), "The settled list must be exactly the store.")
        XCTAssertEqual(ids.count, 200 + 25 * 8 - 25)
        XCTAssertTrue(deleted.isDisjoint(with: ids), "A deleted client is still listed.")
        XCTAssertEqual(
            viewModel.otherClients.map(\.persistentModelID),
            ClientsViewModel.sorted(viewModel.otherClients.shuffled(), by: viewModel.sortOption).map(\.persistentModelID),
            "The settled list is out of order."
        )
    }

    // MARK: - Past the old 1,000-client cap

    /// The list used to load at most 1,000 clients (chosen by a binary,
    /// case-sensitive SQL sort) with no Load More: everyone past that was
    /// invisible, and the filters only saw that window.
    func testABookLargerThanAThousandIsListedWholeInEverySortAndFilter() async throws {
        let size = 2_500
        let clients = try ClientStressDataset.seed(into: context, count: size)
        // Sorts last in any order the old SQL window used, so it was always cut.
        let lateAccent = makeClient("Ñandú", "Ézé")
        try context.save()
        let viewModel = await makeViewModel()

        for option in ClientsViewModel.SortOption.allCases {
            viewModel.sortOption = option
            await viewModel.waitForPendingFetch()
            let ids = listedIDs(viewModel)
            XCTAssertEqual(ids.count, size + 1, "\(option) shows \(ids.count) of \(size + 1)")
            assertListedOnce(viewModel)
            XCTAssertTrue(ids.contains(lateAccent.persistentModelID), "\(option) hides the accented client")
            XCTAssertEqual(
                viewModel.otherClients.map(\.persistentModelID),
                ClientsViewModel.sorted(viewModel.otherClients.shuffled(), by: option).map(\.persistentModelID),
                "\(option) is out of order"
            )
        }

        viewModel.sortOption = .lastName
        viewModel.selectedFilter = .missingInfo
        await viewModel.waitForPendingFetch()
        XCTAssertEqual(listedIDs(viewModel).count, (clients + [lateAccent]).filter(ClientMissingInfo.isIncomplete).count)
    }

    /// A refresh that a newer one replaces is cancelled, and the cancel must
    /// reach the detached read rather than let it finish a full-book pass
    /// nobody will use (a burst of filter taps would stack them up).
    func testCancellingAListReadStopsTheBackgroundWork() async throws {
        try ClientStressDataset.seed(into: context, count: 2_500)
        let repository = ClientRepository(modelContainer: container)

        let read = Task { try await repository.fetchClientList(query: "a", filter: .all, sort: .lastName) }
        read.cancel()

        do {
            _ = try await read.value
            XCTFail("A cancelled read still returned a list.")
        } catch is CancellationError {
            // Expected.
        }

        // And the repository still answers the next read.
        let list = try await repository.fetchClientList(query: "", filter: .all, sort: .lastName)
        XCTAssertEqual(list.inProgress.count + list.others.count, 2_500)
    }

    /// Main-actor and total time for one refresh of a 2,500-client book.
    func testPerformanceOfRefreshingTwentyFiveHundredClients() throws {
        try ClientStressDataset.seed(into: context, count: 2_500)
        let viewModel = ClientsViewModel(modelContext: context)

        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()]) {
            let done = expectation(description: "refresh")
            Task { @MainActor in
                await self.refresh(viewModel)
                done.fulfill()
            }
            wait(for: [done], timeout: 60)
        }
        XCTAssertEqual(listedIDs(viewModel).count, 2_500)
    }

    // MARK: - Sorting

    func testEveryOrderIsRepeatableAcrossRefreshesOfTheStressBook() async throws {
        try ClientStressDataset.seed(into: context, count: bookSize)
        let viewModel = await makeViewModel()

        for option in ClientsViewModel.SortOption.allCases {
            viewModel.sortOption = option
            await viewModel.waitForPendingFetch()
            let first = viewModel.otherClients.map(\.persistentModelID)
            await refresh(viewModel)
            XCTAssertEqual(viewModel.otherClients.map(\.persistentModelID), first, "\(option) reshuffles on refresh")

            // Whatever order the store hands rows back in.
            for _ in 0..<3 {
                let reordered = ClientsViewModel.sorted(viewModel.otherClients.shuffled(), by: option)
                XCTAssertEqual(reordered.map(\.persistentModelID), first, "\(option) depends on input order")
            }
        }
    }

    func testLastNameOrderIgnoresCaseAccentsAndWhitespaceAndPutsNamelessLast() throws {
        let zeta = makeClient("Al", "zeta")
        let alpha = makeClient("Al", "Alpha")
        let emile = makeClient("Al", "émile")
        let bravo = makeClient("Al", "BRAVO")
        let carl = makeClient("Carl", "")           // no last name: files under "Carl"
        let nameless = makeClient("", "")
        let padded = Client(firstName: "", lastName: "")
        padded.firstName = "Al"
        padded.lastName = "   Delta"                // an import kept the spaces
        context.insert(padded)
        try context.save()

        let sorted = ClientsViewModel.sorted([nameless, zeta, padded, carl, emile, bravo, alpha], by: .lastName)

        XCTAssertEqual(sorted.map(\.persistentModelID), [alpha, bravo, carl, padded, emile, zeta, nameless].map(\.persistentModelID))
    }

    func testFirstNameOrderUsesNumericAwareComparison() throws {
        let ten = makeClient("Client 10", "X")
        let nine = makeClient("Client 9", "X")
        let lower = makeClient("client 100", "X")
        try context.save()

        let sorted = ClientsViewModel.sorted([lower, ten, nine], by: .firstName)

        XCTAssertEqual(sorted.map(\.persistentModelID), [nine, ten, lower].map(\.persistentModelID))
    }

    func testDuplicateNamesKeepOneOrder() throws {
        let twins = (0..<30).map { _ in makeClient("Maria", "Lopez") }
        try context.save()

        let reference = ClientsViewModel.sorted(twins, by: .lastName).map(\.persistentModelID)
        for option in ClientsViewModel.SortOption.allCases {
            for _ in 0..<5 {
                XCTAssertEqual(ClientsViewModel.sorted(twins.shuffled(), by: option).count, twins.count)
            }
        }
        for _ in 0..<10 {
            XCTAssertEqual(ClientsViewModel.sorted(twins.shuffled(), by: .lastName).map(\.persistentModelID), reference)
        }
    }

    func testPetNameOrderUsesTheAlphabeticallyFirstPetAndPutsPetlessLast() throws {
        // Zed's first pet by name is "apple"; the card lists it first too.
        let zed = makeClient("Zed", "Zulu", pets: ["Yoyo", "apple"])
        let amy = makeClient("Amy", "Able", pets: ["Biscuit"])
        let petless = makeClient("Aaron", "Aaronson")
        let blankPet = makeClient("Bea", "Blank", pets: ["  "])
        try context.save()

        let sorted = ClientsViewModel.sorted([petless, amy, blankPet, zed], by: .petName)

        XCTAssertEqual(sorted.map(\.persistentModelID), [zed, amy, petless, blankPet].map(\.persistentModelID))
    }

    func testLastVisitOrderIsNewestFirstThenByNameWithNeverVisitedLast() throws {
        let day = Date(timeIntervalSince1970: 1_750_000_000)
        let neverB = makeClient("Bo", "Bravo")
        let neverA = makeClient("Al", "Alpha")
        let older = makeClient("Old", "Visit", lastVisit: day)
        let newerZ = makeClient("Zoe", "Zulu", lastVisit: day.addingTimeInterval(86_400))
        let newerA = makeClient("Ann", "Able", lastVisit: day.addingTimeInterval(86_400))
        try context.save()

        let sorted = ClientsViewModel.sorted([neverB, older, neverA, newerZ, newerA], by: .lastVisit)

        XCTAssertEqual(sorted.map(\.persistentModelID), [newerA, newerZ, older, neverA, neverB].map(\.persistentModelID))
    }

    // MARK: - Search

    func testSearchFindsNamesRegardlessOfCaseAccentsAndNormalization() async throws {
        try ClientStressDataset.seed(into: context, count: bookSize)
        let precomposed = makeClient("José", "Probe")
        let decomposed = makeClient("Jose\u{301}", "Probe")
        try context.save()
        let viewModel = await makeViewModel()

        for query in ["jose probe", "JOSÉ", "Jose\u{301} Probe", "  jose  "] {
            let ids = Set(await search(viewModel, query).map(\.persistentModelID))
            XCTAssertTrue(ids.contains(precomposed.persistentModelID), "'\(query)' missed precomposed José")
            XCTAssertTrue(ids.contains(decomposed.persistentModelID), "'\(query)' missed decomposed José")
        }
    }

    func testSearchMatchesTheNameAsTheListShowsIt() async throws {
        let jane = makeClient("Jane", "Doe")
        try context.save()
        let viewModel = await makeViewModel()

        XCTAssertEqual(await search(viewModel, "Jane Doe").map(\.persistentModelID), [jane.persistentModelID])
        XCTAssertEqual(await search(viewModel, "doe jane").map(\.persistentModelID), [jane.persistentModelID],
                       "The list reads 'Doe Jane' under Last Name; typing that must find her.")
    }

    func testSearchFindsPhonesInAnyFormatIncludingUnparseableOnes() async throws {
        try ClientStressDataset.seed(into: context, count: bookSize)
        let normalized = makeClient("Phone", "Normalized", phone: "312.555.0177")
        let imported = Client(firstName: "Phone", lastName: "Imported")
        imported.phone = "+1 (312) 555-0188"          // stored as typed, not E.164
        context.insert(imported)
        let garbage = Client(firstName: "Phone", lastName: "Garbage")
        garbage.phone = "555-CALL-NOW"
        context.insert(garbage)
        try context.save()
        let viewModel = await makeViewModel()

        for query in ["3125550177", "(312) 555-0177", "555-0177", "+13125550177", "p:0177"] {
            XCTAssertTrue(await search(viewModel, query).contains { $0 === normalized }, "'\(query)' missed the E.164 phone")
        }
        for query in ["3125550188", "312 555 0188", "p:(312) 555-0188"] {
            XCTAssertTrue(await search(viewModel, query).contains { $0 === imported }, "'\(query)' missed the imported phone")
        }
        XCTAssertTrue(await search(viewModel, "CALL-NOW").contains { $0 === garbage })
    }

    func testFieldPrefixesSearchOnlyThatField() async throws {
        try ClientStressDataset.seed(into: context, count: bookSize)
        let viewModel = await makeViewModel()

        let byLast = await search(viewModel, "l:lopez")
        XCTAssertFalse(byLast.isEmpty)
        XCTAssertTrue(byLast.allSatisfy { folded($0.lastName).contains("lopez") }, "l: matched outside the last name")

        let byPet = await search(viewModel, "pet:bella")
        XCTAssertFalse(byPet.isEmpty)
        XCTAssertTrue(byPet.allSatisfy { ($0.pets ?? []).contains { folded($0.name).contains("bella") } })

        XCTAssertTrue(await search(viewModel, "nosuchfield:abc").isEmpty)
    }

    func testHostileQueriesAreLiteralAndHarmless() async throws {
        try ClientStressDataset.seed(into: context, count: bookSize)
        let before = try storeCount()
        let viewModel = await makeViewModel()

        let injection = await search(viewModel, "'); DROP TABLE")
        XCTAssertFalse(injection.isEmpty)
        XCTAssertTrue(injection.allSatisfy { $0.firstName.contains("DROP TABLE") })

        // `%` and `_` are not wildcards.
        let percent = await search(viewModel, "%_%")
        XCTAssertTrue(percent.allSatisfy { $0.firstName.contains("%_%") || $0.lastName.contains("%_%") })

        for query in ["\\", "\"", "🐶", "👩🏽‍⚕️", "\u{200B}", "محمد", "山田", String(repeating: "x", count: 5_000)] {
            _ = await search(viewModel, query)
            assertListedOnce(viewModel)
        }
        XCTAssertEqual(try storeCount(), before, "A search changed the store.")
    }

    func testEmptyAndWhitespaceQueriesListEveryone() async throws {
        try ClientStressDataset.seed(into: context, count: bookSize)
        let viewModel = await makeViewModel()

        for query in ["", " ", "\n\t "] {
            XCTAssertEqual(await search(viewModel, query).count, bookSize, "'\(query.debugDescription)' hid clients")
        }
    }

    /// Accuracy against an independent oracle: every client whose name holds
    /// the query is found (none lost to a fetch window), and nothing else.
    func testNameSearchFindsExactlyTheMatchingClientsInTheStressBook() async throws {
        let clients = try ClientStressDataset.seed(into: context, count: bookSize)
        let viewModel = await makeViewModel()

        for query in ["maria", "an", "ü", "🐾", "Featherstonehaugh", "van houten"] {
            let needle = folded(query)
            let expected = Set(clients.filter { client in
                let names = [client.firstName, client.lastName, client.fullName, client.displayName(lastNameFirst: true)]
                    + (client.pets ?? []).map(\.name)
                return names.contains { folded($0).contains(needle) }
            }.map(\.persistentModelID))
            let found = Set(await search(viewModel, query).map(\.persistentModelID))

            XCTAssertTrue(expected.isSubset(of: found), "'\(query)' missed \(expected.subtracting(found).count) client(s)")
            // A digit-free query can also match a phone's letters ("555-CALL-NOW").
            let extra = found.subtracting(expected).compactMap { context.model(for: $0) as? Client }
            XCTAssertTrue(extra.allSatisfy { folded($0.phone ?? "").contains(needle) }, "'\(query)' matched unrelated clients")
        }
    }

    // MARK: - Filters

    func testSmartFiltersStayAccurateUnderLoad() async throws {
        let clients = try ClientStressDataset.seed(into: context, count: bookSize)
        // Five clients in session, so Active has something to show.
        for client in clients.prefix(5) {
            let pet = Pet(name: "Session Pup", species: .dog)
            pet.owner = client
            context.insert(pet)
            context.insert(Visit(pet: pet))
        }
        try context.save()
        let viewModel = await makeViewModel()

        viewModel.selectedFilter = .active
        await viewModel.waitForPendingFetch()
        XCTAssertEqual(Set(viewModel.inProgressClients.map(\.persistentModelID)), Set(clients.prefix(5).map(\.persistentModelID)))
        XCTAssertTrue(viewModel.otherClients.isEmpty)

        viewModel.selectedFilter = .missingInfo
        await viewModel.waitForPendingFetch()
        let incomplete = viewModel.inProgressClients + viewModel.otherClients
        XCTAssertEqual(incomplete.count, clients.filter(ClientMissingInfo.isIncomplete).count)
        XCTAssertTrue(incomplete.allSatisfy(ClientMissingInfo.isIncomplete))

        viewModel.selectedFilter = .overdue
        await viewModel.waitForPendingFetch()
        XCTAssertTrue(viewModel.inProgressClients.isEmpty)
        XCTAssertTrue(viewModel.otherClients.allSatisfy { ($0.pets ?? []).contains { $0.needsAttention } })

        viewModel.selectedFilter = .all
        await viewModel.waitForPendingFetch()
        XCTAssertEqual(listedIDs(viewModel).count, bookSize)
        assertListedOnce(viewModel)
    }

    // MARK: - Performance

    func testPerformanceOfFullListLoadAtSixHundredClients() throws {
        try ClientStressDataset.seed(into: context, count: bookSize)
        let viewModel = ClientsViewModel(modelContext: context)

        measure(metrics: [XCTClockMetric()]) {
            let done = expectation(description: "fetch")
            Task { @MainActor in
                await self.refresh(viewModel)
                done.fulfill()
            }
            wait(for: [done], timeout: 30)
        }
        XCTAssertEqual(listedIDs(viewModel).count, bookSize)
    }

    /// One fetch per keystroke, as if the debounce never coalesced them.
    func testPerformanceOfTypingASearchAtSixHundredClients() throws {
        try ClientStressDataset.seed(into: context, count: bookSize)
        let viewModel = ClientsViewModel(modelContext: context)

        measure(metrics: [XCTClockMetric()]) {
            let done = expectation(description: "typing")
            Task { @MainActor in
                var typed = ""
                for character in "maria lo" {
                    typed.append(character)
                    _ = await self.search(viewModel, typed)
                }
                done.fulfill()
            }
            wait(for: [done], timeout: 60)
        }
    }

    func testSortingSixHundredClientsStaysFast() throws {
        let clients = try ClientStressDataset.seed(into: context, count: bookSize)

        measure(metrics: [XCTClockMetric()]) {
            for option in ClientsViewModel.SortOption.allCases {
                _ = ClientsViewModel.sorted(clients, by: option)
            }
        }
    }
}
