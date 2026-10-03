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

    /// Matches the complete candidate set before paging, including pet and phone queries.
    func fetchClients(query: String, limit: Int, offset: Int) async throws -> [PersistentIdentifier] {
        let trimmed = query.trimmed
        let context = ModelContext(modelContainer)
        var descriptor = FetchDescriptor<Client>(sortBy: [SortDescriptor(\.lastName), SortDescriptor(\.firstName)])
        if trimmed.isEmpty {
            descriptor.fetchOffset = max(0, offset)
            descriptor.fetchLimit = max(0, limit)
            return try context.fetch(descriptor).map(\.persistentModelID)
        }
        let filtered = try context.fetch(descriptor).filter { Self.matches(client: $0, query: trimmed) }
        return Array(filtered.dropFirst(max(0, offset)).prefix(max(0, limit))).map(\.persistentModelID)
    }

    private func activeClientIDs() throws -> Set<PersistentIdentifier> {
        let freshContext = ModelContext(modelContext.container)
        var activeVisitDesc = FetchDescriptor<Visit>(
            predicate: #Predicate { $0.endedAt == nil }
        )
        activeVisitDesc.relationshipKeyPathsForPrefetching = [\Visit.pet]
        let activeVisits = try freshContext.fetch(activeVisitDesc)
        return Set(activeVisits.compactMap { $0.pet?.owner?.persistentModelID })
    }

    func fetchActiveClients(query: String) async throws -> [PersistentIdentifier] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let activeIDs = try activeClientIDs()
        if activeIDs.isEmpty { return [] }

        let freshContext = ModelContext(modelContainer)
        var results: [Client] = []
        for id in activeIDs {
            if let client = freshContext.model(for: id) as? Client {
                results.append(client)
            }
        }

        if !trimmed.isEmpty {
            results = results.filter { Self.matches(client: $0, query: trimmed) }
        }
        let sorted = results.sorted { $0.sortKeyMostRecentVisit > $1.sortKeyMostRecentVisit }
        return sorted.map { $0.persistentModelID }
    }

    /// Pages after excluding active owners and matching all search tokens.
    func fetchInactiveClients(query: String, limit: Int, offset: Int) async throws -> ([PersistentIdentifier], Bool) {
        let trimmed = query.trimmed
        let activeIDs = try activeClientIDs()
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<Client>(sortBy: [SortDescriptor(\.lastName), SortDescriptor(\.firstName)])
        let inactive = try context.fetch(descriptor)
            .filter { !activeIDs.contains($0.persistentModelID) }
            .filter { trimmed.isEmpty || Self.matches(client: $0, query: trimmed) }
        let start = min(max(0, offset), inactive.count)
        let page = Array(inactive.dropFirst(start).prefix(max(0, limit)))
        return (page.map(\.persistentModelID), start + page.count < inactive.count)
    }

    /// Uses the same normalized token matcher for every repository query path.
    private static func matches(client: Client, query: String) -> Bool {
        client.matches(searchQuery: query)
    }

    /// Removes the optional US country code for legacy phone duplicate checks.
    private static func canonicalPhoneDigits(_ value: String) -> String {
        let digits = PhoneUtils.normalize(value)
        return digits.count == 11 && digits.first == "1" ? String(digits.dropFirst()) : digits
    }

    func findClient(byPhone phone: String) async throws -> PersistentIdentifier? {
        let lookupPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lookupPhone.isEmpty else { return nil }

        // Try the input as-given first (handles canonical E.164 stored phones).
        let exact = FetchDescriptor<Client>(predicate: #Predicate<Client> { client in
            client.phone == lookupPhone
        })
        if let hit = try modelContext.fetch(exact).first {
            return hit.persistentModelID
        }

        // Fall back to normalizing the lookup so we still match clients whose
        // stored phone couldn't be parsed into E.164 at write time.
        guard let normalized = PhoneUtils.toE164(lookupPhone) else {
            return nil
        }
        if normalized != lookupPhone {
            let normalizedDescriptor = FetchDescriptor<Client>(predicate: #Predicate<Client> { client in
                client.phone == normalized
            })
            if let hit = try modelContext.fetch(normalizedDescriptor).first {
                return hit.persistentModelID
            }
        }

        let phonesDescriptor = FetchDescriptor<Client>(predicate: #Predicate<Client> { client in
            client.phone != nil
        })
        let normalizedLookupDigits = Self.canonicalPhoneDigits(normalized)
        return try modelContext.fetch(phonesDescriptor).first { client in
            guard let storedPhone = client.phone else { return false }
            return Self.canonicalPhoneDigits(storedPhone) == normalizedLookupDigits
        }?.persistentModelID
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
        
        var emergencyContacts: [EmergencyContact] = []
        for cd in contacts {
            let contact = EmergencyContact(name: cd.name, relation: cd.relation, phone: cd.phone)
            contact.owner = client
            modelContext.insert(contact)
            emergencyContacts.append(contact)
        }
        client.emergencyContacts = emergencyContacts
        
        modelContext.insert(AppNotification(
            title: AppLocalization.localized("clients.notification.client_created_title", value: "Client Created"),
            message: client.fullName,
            sourceKey: "client-created-\(client.uuid)"
        ))
        do { try modelContext.save() }
        catch { modelContext.rollback(); throw error }
        // The setters above indexed the client before its pets were attached,
        // and each pet before it had an owner. Index the saved state so the
        // client shows its pets and each pet is found by the owner's phone.
        SpotlightIndexer.shared.scheduleIndex(client: client, includingPets: true)
        return client.persistentModelID
    }

    func saveClient(id: PersistentIdentifier, firstName: String, lastName: String, phone: String, email: String) async throws {
        guard let client = modelContext.model(for: id) as? Client else { return }
        client.setFirstName(firstName)
        client.setLastName(lastName)
        client.setPhone(phone)
        client.setEmail(email)
        try modelContext.save()
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

        let cal = Calendar.current
        var affectedDays: Set<Date> = []
        for date in paymentDates { affectedDays.insert(cal.startOfDay(for: date)) }
        for date in visitActivityDates { affectedDays.insert(cal.startOfDay(for: date)) }
        for day in affectedDays {
            SummaryUpdater.rebuildDay(for: day, in: modelContext)
        }
    }
}
