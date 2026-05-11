//
//  ClientRepository.swift
//  Pawtrackr
//
//  Elite background actor for Client data operations.
//  Ensures that large dataset searches and filtering never hitch the main thread.
//

import Foundation
import SwiftData
import OSLog

private let clientRepoLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "ClientRepository")

struct NewPetData: Sendable {
    let name: String
    let species: Species
    let gender: PetGender
    let breed: String?
    let color: String?
    let photoData: Data?
    let health: String?
    let behaviorTags: [String]
    let birthdate: Date?
}

struct NewContactData: Sendable {
    let name: String
    let relation: String?
    let phone: String
}

protocol ClientRepositoryProtocol: Sendable {
    func fetchClients(query: String, limit: Int, offset: Int) async throws -> [PersistentIdentifier]
    func fetchActiveClients(query: String) async throws -> [PersistentIdentifier]
    func fetchInactiveClients(query: String, limit: Int, offset: Int) async throws -> ([PersistentIdentifier], Bool)
    func findClient(byPhone phone: String) async throws -> PersistentIdentifier?
    func createClient(
        firstName: String,
        lastName: String,
        phone: String,
        email: String,
        address: String,
        pets: [NewPetData],
        contacts: [NewContactData]
    ) async throws -> PersistentIdentifier
    func saveClient(id: PersistentIdentifier, firstName: String, lastName: String, phone: String, email: String) async throws
    func deleteClient(id: PersistentIdentifier) async throws
}

@ModelActor
final actor ClientRepository: ClientRepositoryProtocol {

    func fetchClients(query: String, limit: Int, offset: Int) async throws -> [PersistentIdentifier] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var descriptor = FetchDescriptor<Client>(
            sortBy: [SortDescriptor(\.lastName), SortDescriptor(\.firstName)]
        )

        if trimmed.isEmpty {
            descriptor.fetchLimit = limit
            descriptor.fetchOffset = offset
            let all = try modelContext.fetch(descriptor)
            return all.map { $0.persistentModelID }
        }

        descriptor.fetchLimit = 5000
        let all = try modelContext.fetch(descriptor)
        let filtered = all.filter { Self.matches(client: $0, query: trimmed) }
        
        let pageStart = min(offset, filtered.count)
        let pageEnd = min(offset + limit, filtered.count)
        return filtered[pageStart..<pageEnd].map { $0.persistentModelID }
    }

    private func activeClientIDs() throws -> Set<PersistentIdentifier> {
        var activeVisitDesc = FetchDescriptor<Visit>(
            predicate: #Predicate { $0.endedAt == nil }
        )
        activeVisitDesc.fetchLimit = 500
        activeVisitDesc.relationshipKeyPathsForPrefetching = [\Visit.pet]
        let activeVisits = try modelContext.fetch(activeVisitDesc)
        return Set(activeVisits.compactMap { $0.pet?.owner?.persistentModelID })
    }

    func fetchActiveClients(query: String) async throws -> [PersistentIdentifier] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let activeIDs = try activeClientIDs()
        if activeIDs.isEmpty { return [] }

        var results: [Client] = []
        for id in activeIDs {
            if let client = modelContext.model(for: id) as? Client {
                results.append(client)
            }
        }

        if !trimmed.isEmpty {
            results = results.filter { Self.matches(client: $0, query: trimmed) }
        }
        let sorted = results.sorted { $0.sortKeyMostRecentVisit > $1.sortKeyMostRecentVisit }
        return sorted.map { $0.persistentModelID }
    }

    func fetchInactiveClients(query: String, limit: Int, offset: Int) async throws -> ([PersistentIdentifier], Bool) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let activeIDs = try activeClientIDs()

        if trimmed.isEmpty {
            var descriptor = FetchDescriptor<Client>(
                sortBy: [SortDescriptor(\.lastName), SortDescriptor(\.firstName)]
            )
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = limit + activeIDs.count + 1
            let raw = try modelContext.fetch(descriptor)
            let filtered = raw.filter { !activeIDs.contains($0.persistentModelID) }
            let page = Array(filtered.prefix(limit))
            let canLoadMore = filtered.count > limit || raw.count == descriptor.fetchLimit
            return (page.map { $0.persistentModelID }, canLoadMore)
        }

        var allDescriptor = FetchDescriptor<Client>(
            sortBy: [SortDescriptor(\.lastName), SortDescriptor(\.firstName)]
        )
        allDescriptor.fetchLimit = 5000
        let inactive = try modelContext.fetch(allDescriptor)
            .filter { !activeIDs.contains($0.persistentModelID) }
            .filter { Self.matches(client: $0, query: trimmed) }

        let pageStart = min(offset, inactive.count)
        let pageEnd = min(offset + limit, inactive.count)
        let page = inactive[pageStart..<pageEnd]
        let canLoadMore = pageEnd < inactive.count
        return (page.map { $0.persistentModelID }, canLoadMore)
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

    func findClient(byPhone phone: String) async throws -> PersistentIdentifier? {
        let descriptor = FetchDescriptor<Client>(predicate: #Predicate { $0.phone == phone })
        return try modelContext.fetch(descriptor).first?.persistentModelID
    }

    func createClient(
        firstName: String,
        lastName: String,
        phone: String,
        email: String,
        address: String,
        pets: [NewPetData],
        contacts: [NewContactData]
    ) async throws -> PersistentIdentifier {
        let client = Client(firstName: firstName, lastName: lastName, phone: phone, email: email)
        client.address = address
        modelContext.insert(client)
        
        for pd in pets {
            let pet = Pet(name: pd.name, species: pd.species, gender: pd.gender)
            pet.breed = pd.breed
            pet.color = pd.color
            pet.photoData = pd.photoData
            pet.notes = pd.health
            pet.behaviorTags = pd.behaviorTags
            pet.birthdate = pd.birthdate
            pet.owner = client
            modelContext.insert(pet)
        }
        
        for cd in contacts {
            let contact = EmergencyContact(name: cd.name, relation: cd.relation, phone: cd.phone)
            contact.owner = client
            modelContext.insert(contact)
        }
        
        try modelContext.save()
        return client.persistentModelID
    }

    func saveClient(id: PersistentIdentifier, firstName: String, lastName: String, phone: String, email: String) async throws {
        guard let client = modelContext.model(for: id) as? Client else { return }
        client.firstName = firstName
        client.lastName = lastName
        client.phone = phone
        client.email = email
        try modelContext.save()
    }

    func deleteClient(id: PersistentIdentifier) async throws {
        guard let client = modelContext.model(for: id) as? Client else { return }
        
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
