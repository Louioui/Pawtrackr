//
//  ClientListChaosTests.swift
//  PawtrackrTests (QualityControl)
//
//  Tries to break the client list and its store rather than exercise it:
//
//  - 1,000 clients written off the main actor while the main actor deletes,
//    searches, filters and re-sorts, with a memory warning mid-write;
//  - typing faster than 50 keystrokes a second into search;
//  - poisoned names (10,000 characters, Zalgo, invisible, bidi, emoji)
//    through the list, search, sort and the card at the largest text size;
//  - clients deleted while another context keeps adding and editing their
//    pets, with visits underneath (cascade integrity);
//  - memory while writing a large book in chunks.
//
//  Everything crossing an actor boundary is Sendable: specs, IDs, UUIDs
//  and counts. Models never leave the context that fetched them.
//

import XCTest
import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif
@testable import Pawtrackr

@MainActor
final class ClientListChaosTests: XCTestCase {
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

    private func storeCount<T: PersistentModel>(_ type: T.Type, in context: ModelContext? = nil) throws -> Int {
        try (context ?? self.context).fetchCount(FetchDescriptor<T>())
    }

    private func settle(_ viewModel: ClientsViewModel) async {
        viewModel.searchText = ""
        viewModel.selectedFilter = .all
        viewModel.fetchClients()
        await viewModel.waitForPendingFetch()
    }

    private func listedIDs(_ viewModel: ClientsViewModel) -> [PersistentIdentifier] {
        (viewModel.inProgressClients + viewModel.otherClients).map(\.persistentModelID)
    }

    // MARK: - 1. Concurrency bombing

    func testThousandBackgroundInsertsWhileTheMainActorDeletesSearchesAndFilters() async throws {
        try ClientStressDataset.seed(into: context, count: 200)
        let viewModel = ClientsViewModel(modelContext: context)
        await viewModel.waitForPendingFetch()

        let writer = ClientStressWriter(modelContainer: container)
        let specs = ClientStressDataset.makeSpecs(count: 1_000, seed: 99)
        let writing = Task.detached { try await writer.insert(specs, chunkSize: 50) }

        var rng = SplitMix64(seed: 3)
        var deleted = Set<PersistentIdentifier>()
        var failedSaves: [String] = []
        let queries = ["", "maria", "lo", "🐶", "de la", "312", "zz", "Mar", ""]

        for step in 0..<250 {
            // Delete any client, the writer's newest included.
            let count = try storeCount(Client.self)
            var pick = FetchDescriptor<Client>()
            pick.fetchOffset = rng.int(in: 0...max(0, count - 1))
            pick.fetchLimit = 1
            if let victim = try context.fetch(pick).first {
                let id = victim.persistentModelID
                context.delete(victim)
                do {
                    try context.save()
                    deleted.insert(id)
                } catch {
                    context.rollback()
                    failedSaves.append(String(describing: error))
                }
            }

            viewModel.searchText = queries[step % queries.count]
            if step.isMultiple(of: 7) { viewModel.selectedFilter = rng.pick(ClientsViewModel.Filter.allCases) }
            if step.isMultiple(of: 11) { viewModel.sortOption = rng.pick(ClientsViewModel.SortOption.allCases) }
            if step.isMultiple(of: 5) { viewModel.fetchClients() }
            #if canImport(UIKit)
            if step == 120 {
                NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
            }
            #endif
            try await Task.sleep(for: .milliseconds(2))
        }

        let report = try await writing.value
        await settle(viewModel)

        XCTAssertEqual(report.inserted, 1_000)
        XCTAssertEqual(report.chunks, 20)
        XCTAssertEqual(failedSaves, [], "The main context could not save its deletes under contention.")
        let total = try storeCount(Client.self)
        XCTAssertEqual(total, 200 + 1_000 - deleted.count, "A write or a delete was lost.")

        let ids = listedIDs(viewModel)
        XCTAssertEqual(ids.count, total, "The settled list isn't the store.")
        XCTAssertEqual(Set(ids).count, ids.count, "A client is listed twice.")
        XCTAssertTrue(deleted.isDisjoint(with: ids), "A deleted client is still listed.")

        // A context that never saw the churn reads the same store.
        XCTAssertEqual(try storeCount(Client.self, in: ModelContext(container)), total)
    }

    // MARK: - 2. Search fuzzing

    /// More than 60 edits at about 66 a second (typing, a full delete, typing
    /// again). The list must fetch for the settled query, not per keystroke,
    /// no keystroke may block the main actor, and nothing stale may show.
    func testHyperFastTypingIsDebouncedAndEndsOnTheFinalQuery() async throws {
        try ClientStressDataset.seed(into: context, count: 600)
        let repository = CountingClientRepository(container: container)
        let viewModel = ClientsViewModel(modelContext: context, repository: repository)
        await viewModel.waitForPendingFetch()
        let fetchesBefore = repository.inactiveQueries.count

        var edits: [String] = []
        var text = ""
        for character in "the quick brown fox jumps over the lazy dog 12345" {
            text.append(character)
            edits.append(text)
        }
        while !text.isEmpty {
            text.removeLast()
            edits.append(text)
        }
        for character in "maria lo" {
            text.append(character)
            edits.append(text)
        }
        XCTAssertGreaterThan(edits.count, 50)

        let clock = ContinuousClock()
        var slowest = Duration.zero
        for edit in edits {
            let cost = clock.measure { viewModel.searchText = edit }
            slowest = max(slowest, cost)
            try await Task.sleep(for: .milliseconds(15))
        }
        await viewModel.waitForPendingFetch()

        let queries = Array(repository.inactiveQueries.dropFirst(fetchesBefore))
        XCTAssertEqual(queries.last, "maria lo")
        // One fetch when typing settles. A loaded simulator can stall a 15 ms
        // sleep past the 300 ms debounce now and then, so allow a couple.
        XCTAssertLessThanOrEqual(queries.count, 3, "Search fetched \(queries.count) times for \(edits.count) keystrokes.")
        XCTAssertLessThan(slowest, .milliseconds(50), "A keystroke blocked the main actor for \(slowest).")

        let shown = viewModel.inProgressClients + viewModel.otherClients
        XCTAssertFalse(shown.isEmpty)
        XCTAssertTrue(shown.allSatisfy { $0.fullName.localizedCaseInsensitiveContains("maria lo") }, "Stale results from an earlier keystroke.")
    }

    // MARK: - 3. Poisoned data

    func testPoisonedClientsListSortAndSearchWithoutLossOrRepeats() async throws {
        let clients = try ClientStressDataset.seed(into: context, count: 100, includingPoison: true)
        let viewModel = ClientsViewModel(modelContext: context)
        await viewModel.waitForPendingFetch()

        for option in ClientsViewModel.SortOption.allCases {
            viewModel.sortOption = option
            await viewModel.waitForPendingFetch()
            let ids = listedIDs(viewModel)
            XCTAssertEqual(ids.count, clients.count, "\(option)")
            XCTAssertEqual(Set(ids).count, ids.count, "\(option)")
        }

        for query in ["محمد", "🐶", "Wolfeschlegel", "Umlaut", "gnp.exe", "שלום", "ß", "👨‍👩‍👧‍👦", String(repeating: "A", count: 500)] {
            viewModel.searchText = query
            viewModel.fetchClients()
            await viewModel.waitForPendingFetch()
            XCTAssertFalse(listedIDs(viewModel).isEmpty, "Nothing found for \(query.prefix(20).debugDescription)")
        }
    }

    /// The card at the largest accessibility text size, with each poisoned
    /// client, against an ordinary client's card: a name, phone or pet name
    /// may not stretch it (they truncate), and nothing may fail to render.
    func testPoisonedCardsKeepTheirSizeAtTheLargestTextSize() throws {
        let ordinary = Client(firstName: "Jane", lastName: "Doe", phone: "(312) 555-0123")
        context.insert(ordinary)
        for name in ["Bella", "Max"] {
            let pet = Pet(name: name, species: .dog)
            pet.owner = ordinary
            context.insert(pet)
        }
        let poisoned = ClientStressDataset.poisonedSpecs().map { ClientStressDataset.insert($0, into: context) }
        try context.save()

        func height(of client: Client) -> CGFloat? {
            let renderer = ImageRenderer(content:
                ClientCard(client: client, displaysLastNameFirst: true)
                    .frame(width: 360)
                    .dynamicTypeSize(.accessibility5)
            )
            renderer.scale = 1
            return renderer.cgImage.map { CGFloat($0.height) }
        }

        let reference = try XCTUnwrap(height(of: ordinary))
        for client in poisoned {
            let rendered = try XCTUnwrap(height(of: client), "\(client.firstName.prefix(20).debugDescription) didn't render")
            XCTAssertLessThanOrEqual(rendered, reference * 1.6, "\(client.firstName.prefix(20).debugDescription) stretched the card to \(rendered)pt")
        }
    }

    // MARK: - 4. Relationship and cascade strain

    /// The main actor deletes clients while a background context keeps adding
    /// pets to the same clients and editing their existing pets. Afterwards:
    /// no pet or visit points at a deleted client, no pet lost its owner, and
    /// the list matches the store.
    func testDeletingClientsWhileAnotherContextAppendsTheirPetsLeavesNoDanglingRows() async throws {
        let clients = try ClientStressDataset.seed(into: context, count: 150)
        for (index, client) in clients.enumerated() {
            let pet = Pet(name: "Seed \(index)", species: .dog)
            pet.owner = client
            context.insert(pet)
            let visit = Visit(pet: pet, startedAt: Date(timeIntervalSince1970: 1_700_000_000))
            visit.endedAt = visit.startedAt.addingTimeInterval(3_600)
            context.insert(visit)
        }
        try context.save()

        let targets = Array(clients.prefix(100))
        let targetUUIDs = targets.map(\.uuid)
        let churner = PetChurner(modelContainer: container)
        let churning = Task.detached { await churner.churn(clientUUIDs: targetUUIDs, rounds: 4) }

        var failedDeletes = 0
        for client in targets {
            context.delete(client)
            do { try context.save() } catch { context.rollback(); failedDeletes += 1 }
            await Task.yield()
        }
        let churn = await churning.value

        let viewModel = ClientsViewModel(modelContext: context)
        await settle(viewModel)

        // Counted in a fresh context so nothing stale or cached answers.
        let fresh = ModelContext(container)
        let survivors = try fresh.fetch(FetchDescriptor<Client>())
        let petsOfSurvivors = survivors.reduce(0) { $0 + ($1.pets ?? []).count }
        let visitsOfSurvivors = survivors.reduce(0) { total, client in
            total + (client.pets ?? []).reduce(0) { $0 + ($1.visits ?? []).count }
        }
        let orphanPets = try fresh.fetchCount(FetchDescriptor<Pet>(predicate: #Predicate { $0.owner == nil }))

        XCTAssertEqual(failedDeletes, 0)
        XCTAssertEqual(survivors.count, 50)
        XCTAssertEqual(try storeCount(Pet.self, in: fresh), petsOfSurvivors + orphanPets, "A pet points at a deleted client.")
        XCTAssertEqual(orphanPets, 0, "A pet lost its owner (\(churn.appended) appended, \(churn.refused) saves refused).")
        XCTAssertEqual(try storeCount(Visit.self, in: fresh), visitsOfSurvivors, "A visit outlived its client.")

        let ids = listedIDs(viewModel)
        XCTAssertEqual(ids.count, 50)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertGreaterThan(churn.appended + churn.refused, 0, "The churner never ran.")
    }

    // MARK: - 5. Memory

    /// Physical memory while writing 1,000 clients through the chunked writer
    /// (a context per 100). Compare against the baseline Xcode records.
    func testMemoryWhileWritingAThousandClientsInChunks() {
        let writer = ClientStressWriter(modelContainer: container)
        let specs = ClientStressDataset.makeSpecs(count: 1_000, seed: 5)

        measure(metrics: [XCTMemoryMetric(), XCTClockMetric()]) {
            let done = expectation(description: "written")
            Task.detached {
                _ = try? await writer.insert(specs, chunkSize: 100)
                done.fulfill()
            }
            wait(for: [done], timeout: 120)
        }
    }
}

// MARK: - Test doubles

/// The real repository, counting the list's reads.
private final class CountingClientRepository: ClientRepositoryProtocol, @unchecked Sendable {
    private let base: ClientRepository
    private let lock = NSLock()
    private var queries: [String] = []

    init(container: ModelContainer) {
        base = ClientRepository(modelContainer: container)
    }

    var inactiveQueries: [String] { lock.withLock { queries } }

    func fetchInactiveClients(query: String, limit: Int, offset: Int) async throws -> ([PersistentIdentifier], Bool) {
        lock.withLock { queries.append(query) }
        return try await base.fetchInactiveClients(query: query, limit: limit, offset: offset)
    }

    func fetchClients(query: String, limit: Int, offset: Int) async throws -> [PersistentIdentifier] {
        try await base.fetchClients(query: query, limit: limit, offset: offset)
    }

    func fetchActiveClients(query: String) async throws -> [PersistentIdentifier] {
        try await base.fetchActiveClients(query: query)
    }

    func findClient(byPhone phone: String) async throws -> PersistentIdentifier? {
        try await base.findClient(byPhone: phone)
    }

    func createClient(firstName: String, lastName: String, phone: String, email: String, address: String, photoData: Data?, pets: [NewPetData], contacts: [NewContactData]) async throws -> PersistentIdentifier {
        try await base.createClient(firstName: firstName, lastName: lastName, phone: phone, email: email, address: address, photoData: photoData, pets: pets, contacts: contacts)
    }

    func saveClient(id: PersistentIdentifier, firstName: String, lastName: String, phone: String, email: String) async throws {
        try await base.saveClient(id: id, firstName: firstName, lastName: lastName, phone: phone, email: email)
    }

    func deleteClient(id: PersistentIdentifier) async throws {
        try await base.deleteClient(id: id)
    }
}

/// A background writer that keeps adding pets to clients and editing their
/// existing pets, the way a sync or import would. Each round re-fetches the
/// owner by UUID (never trusting a model from an earlier fetch); a save the
/// store refuses is rolled back and counted.
@ModelActor
private actor PetChurner {
    struct Result: Sendable {
        var appended = 0
        var refused = 0
    }

    func churn(clientUUIDs: [UUID], rounds: Int) -> Result {
        var result = Result()
        for round in 0..<rounds {
            for uuid in clientUUIDs {
                var descriptor = FetchDescriptor<Client>(predicate: #Predicate { $0.uuid == uuid })
                descriptor.fetchLimit = 1
                guard let owner = try? modelContext.fetch(descriptor).first else { continue }

                let pet = Pet(name: "Churn \(round)", species: .cat)
                pet.owner = owner
                modelContext.insert(pet)
                for existing in owner.pets ?? [] where existing !== pet {
                    existing.notes = "round \(round)"
                }
                do {
                    try modelContext.save()
                    result.appended += 1
                } catch {
                    modelContext.rollback()
                    result.refused += 1
                }
            }
        }
        return result
    }
}
