//
//  ClientRepository.swift
//  Pawtrackr
//
//  Abstracts SwiftData operations for Clients to allow for better testability and decoupling.
//

import Foundation
import SwiftData

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
        let predicate: Predicate<Client>?
        
        if trimmed.isEmpty {
            predicate = nil
        } else {
            predicate = #Predicate<Client> { client in
                client.firstName.localizedStandardContains(trimmed) || 
                client.lastName.localizedStandardContains(trimmed) ||
                (client.phone.flatMap { $0.localizedStandardContains(trimmed) } ?? false)
            }
        }
        
        var descriptor = FetchDescriptor<Client>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.lastName), SortDescriptor(\.firstName)]
        )
        descriptor.fetchLimit = limit
        descriptor.fetchOffset = offset
        
        return try modelContext.fetch(descriptor)
    }

    func fetchActiveClients(query: String) async throws -> [Client] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let predicate = #Predicate<Client> { client in
            client.pets.contains { pet in pet.visits.contains { visit in visit.endedAt == nil } }
        }

        let descriptor = FetchDescriptor<Client>(predicate: predicate)
        var results = try modelContext.fetch(descriptor)
        if !trimmed.isEmpty {
            results = results.filter { Self.matches(client: $0, query: trimmed) }
        }
        return results.sorted { $0.sortKeyMostRecentVisit > $1.sortKeyMostRecentVisit }
    }

    func fetchInactiveClients(query: String, limit: Int, offset: Int) async throws -> ([Client], Bool) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let predicate = #Predicate<Client> { client in
            !client.pets.contains { pet in pet.visits.contains { visit in visit.endedAt == nil } }
        }

        var descriptor = FetchDescriptor<Client>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.lastName), SortDescriptor(\.firstName)]
        )
        if trimmed.isEmpty {
            descriptor.fetchLimit = limit
            descriptor.fetchOffset = offset
            let results = try modelContext.fetch(descriptor)
            let canLoadMore = results.count == limit
            return (results, canLoadMore)
        }

        // Searching: filter in memory then paginate.
        let all = try modelContext.fetch(descriptor)
        let filtered = all.filter { Self.matches(client: $0, query: trimmed) }
        let pageStart = min(offset, filtered.count)
        let pageEnd = min(offset + limit, filtered.count)
        let page = Array(filtered[pageStart..<pageEnd])
        let canLoadMore = pageEnd < filtered.count
        return (page, canLoadMore)
    }

    private static func matches(client: Client, query: String) -> Bool {
        if client.firstName.localizedStandardContains(query) { return true }
        if client.lastName.localizedStandardContains(query) { return true }
        if let phone = client.phone, phone.localizedStandardContains(query) { return true }
        return client.pets.contains { $0.name.localizedStandardContains(query) }
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
        let pets = Array(client.pets)
        let visits = pets.flatMap { pet in Array(pet.visits) }
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
