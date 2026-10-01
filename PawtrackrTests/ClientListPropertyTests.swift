//
//  ClientListPropertyTests.swift
//  PawtrackrTests
//
//  Stateful property test for the client list. A seeded random sequence of
//  operations (batch insert from a background actor, delete, rename,
//  check-in, check-out, filter, sort, search) runs against a real store,
//  and after every operation the list must hold three invariants:
//
//  1. It shows exactly the clients an independent oracle finds in the
//     store for the current search and filter, in the right section.
//  2. No client (ID or UUID) is listed twice.
//  3. Each section is in `ClientListOrdering` order.
//
//  A failure names the seed, the step and the operations so far. Re-run one
//  with PAWTRACKR_PROPERTY_SEED=<seed>; set PAWTRACKR_PROPERTY_OPS for a
//  longer or shorter run.
//

import XCTest
import SwiftData
@testable import Pawtrackr

@MainActor
final class ClientListPropertyTests: XCTestCase {
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

    private enum Operation: CaseIterable {
        case batchInsert, delete, rename, checkIn, checkOut, filter, sort, search
    }

    /// Space-free and digit-free, so a match can't straddle two fields or
    /// hit a phone number's digits: the oracle below stays exact.
    private let queries = ["", "", "maria", "LOPEZ", "an", "ü", "cruz", "zz", "🐶", "o'"]

    func testListHoldsItsInvariantsThroughARandomOperationSequence() async throws {
        let environment = ProcessInfo.processInfo.environment
        let seed = environment["PAWTRACKR_PROPERTY_SEED"].flatMap(UInt64.init) ?? 0xC11E_5EED
        let operations = environment["PAWTRACKR_PROPERTY_OPS"].flatMap(Int.init) ?? 1_000

        try ClientStressDataset.seed(into: context, count: 150, seed: seed)
        let writer = ClientStressWriter(modelContainer: container)
        let viewModel = ClientsViewModel(modelContext: context)
        await viewModel.waitForPendingFetch()

        var rng = SplitMix64(seed: seed)
        var log: [String] = []

        for step in 0..<operations {
            let operation = rng.pick(Operation.allCases)
            log.append(try await apply(operation, viewModel: viewModel, writer: writer, rng: &rng, step: step))

            viewModel.fetchClients()
            await viewModel.waitForPendingFetch()

            let violations = try invariantViolations(of: viewModel)
            if !violations.isEmpty {
                XCTFail("""
                Seed \(seed), step \(step) of \(operations): \(violations.joined(separator: "; "))
                Last operations: \(log.suffix(12).joined(separator: " → "))
                """)
                return
            }
        }
    }

    // MARK: - Operations

    private func apply(
        _ operation: Operation,
        viewModel: ClientsViewModel,
        writer: ClientStressWriter,
        rng: inout SplitMix64,
        step: Int
    ) async throws -> String {
        switch operation {
        case .batchInsert:
            let count = rng.int(in: 1...8)
            let specs = Array(ClientStressDataset.makeSpecs(count: count + 1, seed: UInt64(step) &* 31 &+ 7).dropFirst())
            let report = try await writer.insert(specs, chunkSize: 3)
            return "insert \(report.inserted)"

        case .delete:
            guard let client = try randomClient(&rng) else { return "delete (empty)" }
            context.delete(client)
            try context.save()
            return "delete"

        case .rename:
            guard let client = try randomClient(&rng) else { return "rename (empty)" }
            if rng.chance(0.5) {
                client.setLastName(rng.pick(ClientStressDataset.edgeLastNames + ClientStressDataset.commonLastNames))
            } else {
                client.setFirstName(rng.pick(ClientStressDataset.edgeFirstNames + ClientStressDataset.commonFirstNames))
            }
            try context.save()
            return "rename"

        case .checkIn:
            guard let client = try randomClient(&rng) else { return "check in (empty)" }
            let pet = Pet(name: "Visit Pup \(step)", species: .dog)
            pet.owner = client
            context.insert(pet)
            context.insert(Visit(pet: pet))
            try context.save()
            return "check in"

        case .checkOut:
            var open = FetchDescriptor<Visit>(predicate: #Predicate { $0.endedAt == nil })
            open.fetchLimit = 20
            guard let visit = try context.fetch(open).randomElement(using: &rng) else { return "check out (none)" }
            visit.endedAt = .now
            try context.save()
            return "check out"

        case .filter:
            let filter = rng.pick(ClientsViewModel.Filter.allCases)
            viewModel.selectedFilter = filter
            return "filter \(filter)"

        case .sort:
            let sort = rng.pick(ClientsViewModel.SortOption.allCases)
            viewModel.sortOption = sort
            return "sort \(sort)"

        case .search:
            let query = rng.pick(queries)
            viewModel.searchText = query
            return "search \(query.debugDescription)"
        }
    }

    private func randomClient(_ rng: inout SplitMix64) throws -> Client? {
        let count = try context.fetchCount(FetchDescriptor<Client>())
        guard count > 0 else { return nil }
        var pick = FetchDescriptor<Client>()
        pick.fetchOffset = rng.int(in: 0...(count - 1))
        pick.fetchLimit = 1
        return try context.fetch(pick).first
    }

    // MARK: - Invariants

    private func invariantViolations(of viewModel: ClientsViewModel) throws -> [String] {
        var violations: [String] = []
        let shownInProgress = viewModel.inProgressClients.map(\.persistentModelID)
        let shownOthers = viewModel.otherClients.map(\.persistentModelID)
        let shown = shownInProgress + shownOthers

        // 1. Exactly the store's answer, read in a fresh context.
        let expected = try oracle(query: viewModel.searchText, filter: viewModel.selectedFilter)
        if Set(shownInProgress) != expected.inProgress {
            violations.append("in session shows \(shownInProgress.count), store has \(expected.inProgress.count)")
        }
        if Set(shownOthers) != expected.others {
            violations.append("all clients shows \(shownOthers.count), store has \(expected.others.count)")
        }

        // 2. Once each.
        if Set(shown).count != shown.count {
            violations.append("\(shown.count - Set(shown).count) repeated ID(s)")
        }
        let uuids = (viewModel.inProgressClients + viewModel.otherClients).map(\.uuid)
        if Set(uuids).count != uuids.count {
            violations.append("repeated UUID")
        }

        // 3. In order.
        for (name, section) in [("in session", viewModel.inProgressClients), ("all clients", viewModel.otherClients)] {
            let reordered = ClientListOrdering.sorted(section.shuffled(), by: viewModel.sortOption)
            if reordered.map(\.persistentModelID) != section.map(\.persistentModelID) {
                violations.append("\(name) not in \(viewModel.sortOption) order")
            }
        }
        return violations
    }

    /// Written apart from the repository: its own context, its own matching.
    private func oracle(query: String, filter: ClientsViewModel.Filter) throws -> (inProgress: Set<PersistentIdentifier>, others: Set<PersistentIdentifier>) {
        let fresh = ModelContext(container)
        let openVisits = try fresh.fetch(FetchDescriptor<Visit>(predicate: #Predicate { $0.endedAt == nil }))
        let active = Set(openVisits.compactMap { $0.pet?.owner?.persistentModelID })

        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let matching = try fresh.fetch(FetchDescriptor<Client>()).filter { client in
            guard !needle.isEmpty else { return true }
            let fields = [client.firstName, client.lastName, client.phone ?? ""] + (client.pets ?? []).map(\.name)
            return fields.contains {
                $0.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).contains(needle)
            }
        }

        var inProgress = matching.filter { active.contains($0.persistentModelID) }
        var others = matching.filter { !active.contains($0.persistentModelID) }
        switch filter {
        case .all:
            break
        case .active:
            others = []
        case .overdue:
            inProgress = []
            others = others.filter { ($0.pets ?? []).contains { $0.needsAttention } }
        case .missingInfo:
            inProgress = inProgress.filter(ClientMissingInfo.isIncomplete)
            others = others.filter(ClientMissingInfo.isIncomplete)
        }
        return (Set(inProgress.map(\.persistentModelID)), Set(others.map(\.persistentModelID)))
    }
}
