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
        photoData: Data?,
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

        // Field-prefixed query (e.g. "n:Sara" / "p:555" / "pet:Bella") still
        // needs the in-memory matcher because we filter against custom views
        // including the joined pet list. Cap the fetch to a smaller window so
        // a salon with thousands of clients doesn't load the entire table per
        // keystroke. Page from the candidate window — pagination beyond that
        // window requires a query refinement.
        let candidateLimit = max(limit * 4, 200)
        descriptor.fetchLimit = candidateLimit

        // For simple unstructured queries, push name match into the predicate
        // first. localizedStandardContains is diacritic+case insensitive.
        if !trimmed.contains(":") {
            descriptor.predicate = #Predicate { client in
                client.lastName.localizedStandardContains(trimmed) ||
                client.firstName.localizedStandardContains(trimmed)
            }
        }

        let all = try modelContext.fetch(descriptor)
        let filtered = all.filter { Self.matches(client: $0, query: trimmed) }

        let pageStart = min(offset, filtered.count)
        let pageEnd = min(offset + limit, filtered.count)
        return filtered[pageStart..<pageEnd].map { $0.persistentModelID }
    }

    private func activeClientIDs() throws -> Set<PersistentIdentifier> {
        let freshContext = ModelContext(modelContext.container)
        var activeVisitDesc = FetchDescriptor<Visit>(
            predicate: #Predicate { $0.endedAt == nil }
        )
        activeVisitDesc.fetchLimit = 500
        activeVisitDesc.relationshipKeyPathsForPrefetching = [\Visit.pet]
        let activeVisits = try freshContext.fetch(activeVisitDesc)
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
        // Try the input as-given first (handles canonical E.164 stored phones).
        let exact = FetchDescriptor<Client>(predicate: #Predicate { $0.phone == phone })
        if let hit = try modelContext.fetch(exact).first {
            return hit.persistentModelID
        }
        // Fall back to normalizing the lookup so we still match clients whose
        // stored phone couldn't be parsed into E.164 at write time.
        guard let normalized = PhoneUtils.toE164(phone), normalized != phone else {
            return nil
        }
        let normalizedDescriptor = FetchDescriptor<Client>(predicate: #Predicate { $0.phone == normalized })
        return try modelContext.fetch(normalizedDescriptor).first?.persistentModelID
    }

    func createClient(
        firstName: String,
        lastName: String,
        phone: String,
        email: String,
        address: String,
        photoData: Data?,
        pets: [NewPetData],
        contacts: [NewContactData]
    ) async throws -> PersistentIdentifier {
        let client = Client(firstName: firstName, lastName: lastName)
        client.setPhone(phone)
        client.setEmail(email)
        client.setAddress(address)
        client.setPhotoData(photoData)
        modelContext.insert(client)
        
        for pd in pets {
            let pet = Pet(name: pd.name, species: pd.species, gender: pd.gender)
            pet.breed = pd.breed
            pet.color = pd.color
            pet.setPhotoData(pd.photoData)
            pet.updateThumbnail()
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
        let clientUUID = client.uuid
        await MainActor.run {
            CloudKitMonitor.shared.recordLocalChange(
                "Created client",
                entityName: "Client",
                recordUUID: clientUUID,
                changedKeys: ["uuid", "firstName", "lastName", "phone", "email", "address", "photoData", "pets", "emergencyContacts", "createdAt", "updatedAt"]
            )
        }
        return client.persistentModelID
    }

    func saveClient(id: PersistentIdentifier, firstName: String, lastName: String, phone: String, email: String) async throws {
        guard let client = modelContext.model(for: id) as? Client else { return }
        client.setFirstName(firstName)
        client.setLastName(lastName)
        client.setPhone(phone)
        client.setEmail(email)
        try modelContext.save()
        let clientUUID = client.uuid
        await MainActor.run {
            CloudKitMonitor.shared.recordLocalChange(
                "Saved client",
                entityName: "Client",
                recordUUID: clientUUID,
                changedKeys: ["firstName", "lastName", "phone", "email", "primaryContactInfo", "updatedAt", "lastModifiedBy"]
            )
        }
    }

    func deleteClient(id: PersistentIdentifier) async throws {
        guard let client = modelContext.model(for: id) as? Client else { return }
        let clientUUID = client.uuid
        
        let pets = Array(client.pets ?? [])
        let petUUIDs = pets.map(\.uuid)
        let visits = pets.flatMap { pet in Array(pet.visits ?? []) }
        let paymentDates = visits.compactMap { $0.payment?.paidAt }
        let visitActivityDates = visits.map { $0.endedAt ?? $0.startedAt }

        modelContext.delete(client)
        try modelContext.save()
        SpotlightIndexer.shared.removeClientAndPetsFromIndex(clientID: clientUUID, petIDs: petUUIDs)
        await MainActor.run {
            CloudKitMonitor.shared.recordLocalChange(
                "Deleted client",
                entityName: "Client",
                recordUUID: clientUUID,
                changedKeys: ["deleted"]
            )
        }

        let cal = Calendar.current
        var affectedDays: Set<Date> = []
        for date in paymentDates { affectedDays.insert(cal.startOfDay(for: date)) }
        for date in visitActivityDates { affectedDays.insert(cal.startOfDay(for: date)) }
        for day in affectedDays {
            SummaryUpdater.rebuildDay(for: day, in: modelContext)
        }
    }
}
