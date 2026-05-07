//
//  ClientRepository.swift
//  Pawtrackr
//
//  Abstracts SwiftData operations for Clients to allow for better testability and decoupling.
//

import Foundation
import SwiftData
import OSLog

private let clientRepoLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "ClientRepository")

@MainActor
protocol ClientRepositoryProtocol: Sendable {
    func fetchClients(query: String, limit: Int, offset: Int) async throws -> [Client]
    func fetchActiveClients(query: String) async throws -> [Client]
    func fetchInactiveClients(query: String, limit: Int, offset: Int) async throws -> ([Client], Bool)
    func findClient(byPhone phone: String) async throws -> Client?
    func saveClient(_ client: Client) async throws
    func deleteClient(_ client: Client) async throws
}

@MainActor
final class ClientRepository: ClientRepositoryProtocol {
    private let modelContext: ModelContext

    init(modelContainer: ModelContainer) {
        self.modelContext = modelContainer.mainContext
    }

    func fetchClients(query: String, limit: Int, offset: Int) async throws -> [Client] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        var descriptor = FetchDescriptor<Client>(
            sortBy: [SortDescriptor(\.lastName), SortDescriptor(\.firstName)]
        )

        do {
            if trimmed.isEmpty {
                descriptor.fetchLimit = limit
                descriptor.fetchOffset = offset
                return try modelContext.fetch(descriptor)
            }

            // SwiftData's #Predicate compiler does not reliably translate
            // localizedStandardContains or flatMap-over-optional patterns,
            // so the search runs in memory. The list is small enough.
            let all = try modelContext.fetch(descriptor)
            let filtered = all.filter { Self.matches(client: $0, query: trimmed) }
            let pageStart = min(offset, filtered.count)
            let pageEnd = min(offset + limit, filtered.count)
            return Array(filtered[pageStart..<pageEnd])
        } catch {
            clientRepoLog.error("fetchClients failed: \(String(describing: error))")
            throw error
        }
    }

    /// Cached active-client IDs. Active visits are bounded by working hours; this
    /// avoids re-walking the full Visit→Pet→Owner chain on every list refresh.
    private func activeClientIDs() throws -> Set<PersistentIdentifier> {
        // Bounded fetch — even a stuck/abandoned active-visit dataset will not
        // grow past this cap, so the menubar/list never freezes on cold start.
        var activeVisitDesc = FetchDescriptor<Visit>(
            predicate: #Predicate { $0.endedAt == nil }
        )
        activeVisitDesc.fetchLimit = 500
        // Prefetch the relationship chain in one round-trip so we don't fault
        // pet/owner per row in a tight loop.
        activeVisitDesc.relationshipKeyPathsForPrefetching = [\Visit.pet, \Visit.pet?.owner]
        let activeVisits = try modelContext.fetch(activeVisitDesc)
        return Set(activeVisits.compactMap { $0.pet?.owner?.persistentModelID })
    }

    func fetchActiveClients(query: String) async throws -> [Client] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let activeIDs = try activeClientIDs()
            if activeIDs.isEmpty { return [] }

            // Bounded by activeIDs.count, which is small (active visits, not all clients).
            // Sorted in-memory by most recent visit — sortKey can't go in #Predicate.
            let activeArray = Array(activeIDs)
            var results: [Client] = []
            results.reserveCapacity(activeArray.count)
            for id in activeArray {
                if let client = modelContext.model(for: id) as? Client {
                    results.append(client)
                }
            }

            if !trimmed.isEmpty {
                results = results.filter { Self.matches(client: $0, query: trimmed) }
            }
            return results.sorted { $0.sortKeyMostRecentVisit > $1.sortKeyMostRecentVisit }
        } catch {
            clientRepoLog.error("fetchActiveClients failed: \(String(describing: error))")
            throw error
        }
    }

    func fetchInactiveClients(query: String, limit: Int, offset: Int) async throws -> ([Client], Bool) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let activeIDs = try activeClientIDs()

            // Free-text search has to fall back to the slow path (in-memory match
            // because SwiftData #Predicate can't express the field-prefix syntax).
            // Otherwise we can paginate at the SwiftData level and avoid loading
            // the whole client table into memory.
            if trimmed.isEmpty {
                // Fast path: page directly from SwiftData, then drop active rows.
                // We over-fetch by activeIDs.count to keep the page exactly `limit`
                // after dropping actives.
                var descriptor = FetchDescriptor<Client>(
                    sortBy: [SortDescriptor(\.lastName), SortDescriptor(\.firstName)]
                )
                descriptor.fetchOffset = offset
                descriptor.fetchLimit = limit + activeIDs.count + 1
                let raw = try modelContext.fetch(descriptor)
                let filtered = raw.filter { !activeIDs.contains($0.persistentModelID) }
                let page = Array(filtered.prefix(limit))
                let canLoadMore = filtered.count > limit || raw.count == descriptor.fetchLimit
                return (page, canLoadMore)
            }

            // Slow path (search): we still need every match to apply the in-memory
            // matcher. Cap defensively so an abusive query can't load 100k rows.
            var allDescriptor = FetchDescriptor<Client>(
                sortBy: [SortDescriptor(\.lastName), SortDescriptor(\.firstName)]
            )
            allDescriptor.fetchLimit = 5000
            let inactive = try modelContext.fetch(allDescriptor)
                .filter { !activeIDs.contains($0.persistentModelID) }
                .filter { Self.matches(client: $0, query: trimmed) }

            let pageStart = min(offset, inactive.count)
            let pageEnd = min(offset + limit, inactive.count)
            let page = Array(inactive[pageStart..<pageEnd])
            let canLoadMore = pageEnd < inactive.count
            return (page, canLoadMore)
        } catch {
            clientRepoLog.error("fetchInactiveClients failed: \(String(describing: error))")
            throw error
        }
    }

    private static func matches(client: Client, query: String) -> Bool {
        let fieldMap: [String: String?] = [
            "n": client.fullName,
            "p": client.phone,
            "f": client.firstName,
            "l": client.lastName,
            "pet": (client.pets ?? []).map { $0.name }.joined(separator: " ")
        ]

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains(":") {
            let parts = trimmed.split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                let prefix = parts[0].lowercased()
                let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                let needle = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)

                if let fieldValue = fieldMap[prefix], let fieldValue = fieldValue {
                    let haystack = fieldValue.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                    return haystack.contains(needle)
                }
                return false
            }
        }

        return SearchEngine.matches(query, in: Array(fieldMap.values))
    }

    func findClient(byPhone phone: String) async throws -> Client? {
        let descriptor = FetchDescriptor<Client>(predicate: #Predicate { $0.phone == phone })
        return try modelContext.fetch(descriptor).first
    }

    func saveClient(_ client: Client) async throws {
        modelContext.insert(client)
        try modelContext.save()
    }

    func deleteClient(_ client: Client) async throws {
        let pets = Array(client.pets ?? [])
        let visits = pets.flatMap { pet in Array(pet.visits ?? []) }
        let paymentDates = visits.compactMap { $0.payment?.paidAt }
        let visitActivityDates = visits.map { $0.endedAt ?? $0.startedAt }

        modelContext.delete(client)
        try modelContext.save()

        let cal = Calendar.current
        var affectedDays: Set<Date> = []
        for date in paymentDates { affectedDays.insert(cal.startOfDay(for: date)) }
        for date in visitActivityDates { affectedDays.insert(cal.startOfDay(for: date)) }
        for day in affectedDays {
            SummaryUpdater.rebuildDay(for: day, in: modelContext)
        }
    }
}
