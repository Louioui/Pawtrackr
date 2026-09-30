//
//  SampleData.swift
//  Pawtrackr
//
//  Identity of the sample salon (the practice clients onboarding can load)
//  and the rules for when it may be loaded.
//

import Foundation
import SwiftData

/// The sample clients, pets and visits `DemoDataSeeder` inserts carry these
/// fixed UUIDs in their existing `uuid` properties. That is the only marker:
/// no model has an "is sample" field, and nothing is ever matched by name,
/// because a real client can share a sample's name.
///
/// Older stores may hold duplicate sample UUIDs, so every lookup here returns
/// all matches, never just the first.
enum SampleData {
    static let avaClientID = UUID(uuidString: "5A3D1E00-0000-4000-8000-00000000C001")!
    static let jordanClientID = UUID(uuidString: "5A3D1E00-0000-4000-8000-00000000C002")!

    static let miloPetID = UUID(uuidString: "5A3D1E00-0000-4000-8000-00000000D001")!
    static let lunaPetID = UUID(uuidString: "5A3D1E00-0000-4000-8000-00000000D002")!

    static let miloActiveVisitID = UUID(uuidString: "5A3D1E00-0000-4000-8000-00000000E001")!
    static let miloRecentVisitID = UUID(uuidString: "5A3D1E00-0000-4000-8000-00000000E002")!
    static let lunaRecentVisitID = UUID(uuidString: "5A3D1E00-0000-4000-8000-00000000E003")!
    static let miloOlderVisitID = UUID(uuidString: "5A3D1E00-0000-4000-8000-00000000E004")!

    /// Ordered: the tour opens the first client that has a checked-in pet.
    static let clientIDList: [UUID] = [avaClientID, jordanClientID]
    static let petIDList: [UUID] = [miloPetID, lunaPetID]
    static let visitIDList: [UUID] = [miloActiveVisitID, miloRecentVisitID, lunaRecentVisitID, miloOlderVisitID]

    static let clientIDs = Set(clientIDList)
    static let petIDs = Set(petIDList)
    static let visitIDs = Set(visitIDList)

    static func isSample(_ client: Client) -> Bool {
        clientIDs.contains(client.uuid)
    }

    static func isSample(_ pet: Pet) -> Bool {
        petIDs.contains(pet.uuid)
    }

    /// Every client row that carries a sample UUID, duplicates included.
    static func sampleClients(in context: ModelContext) throws -> [Client] {
        var clients: [Client] = []
        for id in clientIDList {
            clients += try context.fetch(FetchDescriptor<Client>(predicate: #Predicate { $0.uuid == id }))
        }
        return clients
    }

    static func sampleClientCount(in context: ModelContext) throws -> Int {
        var count = 0
        for id in clientIDList {
            count += try context.fetchCount(FetchDescriptor<Client>(predicate: #Predicate { $0.uuid == id }))
        }
        return count
    }

    /// Clients that aren't sample rows. Counts, never names.
    static func realClientCount(in context: ModelContext) throws -> Int {
        let total = try context.fetchCount(FetchDescriptor<Client>())
        return max(0, total - (try sampleClientCount(in: context)))
    }

    /// Visits that aren't sample data: not a sample visit UUID, not on a
    /// sample pet, and not on any pet of a sample client (removing the
    /// samples removes those too). Counts, never names.
    static func realVisitCount(in context: ModelContext) throws -> Int {
        let total = try context.fetchCount(FetchDescriptor<Visit>())
        guard total > 0 else { return 0 }
        var sampleVisits = Set<PersistentIdentifier>()
        for client in try sampleClients(in: context) {
            for pet in client.pets ?? [] {
                for visit in pet.visits ?? [] { sampleVisits.insert(visit.persistentModelID) }
            }
        }
        for id in petIDList {
            for pet in try context.fetch(FetchDescriptor<Pet>(predicate: #Predicate { $0.uuid == id })) {
                for visit in pet.visits ?? [] { sampleVisits.insert(visit.persistentModelID) }
            }
        }
        for id in visitIDList {
            for visit in try context.fetch(FetchDescriptor<Visit>(predicate: #Predicate { $0.uuid == id })) {
                sampleVisits.insert(visit.persistentModelID)
            }
        }
        return max(0, total - sampleVisits.count)
    }

    /// The sample client the guided tour opens. It prefers one whose pet is
    /// checked in, so the checkout steps have a sample visit to show. Only
    /// sample rows are ever returned: the tour must never open a real client.
    static func tourClient(in context: ModelContext) -> Client? {
        do {
            let clients = try sampleClients(in: context)
            let withActivePet = clients.first { client in
                (client.pets ?? []).contains { pet in (pet.visits ?? []).contains { $0.endedAt == nil } }
            }
            return withActivePet
                ?? clients.first { !($0.pets ?? []).isEmpty }
                ?? clients.first
        } catch {
            return nil
        }
    }
}

/// Sample clients may only be added to an empty local salon. Existing records
/// and recovery backups take precedence; Settings can add samples later.
enum SampleDataSeedPolicy {
    enum SkipReason: Equatable, Sendable {
        case notChosen
        /// A business profile existed before setup, or clients or pets exist.
        case salonHasData
        /// A backup on this device holds clients the store is missing.
        case backupFound
    }

    enum Decision: Equatable, Sendable {
        case seed
        case skip(SkipReason)
    }

    struct Inputs: Equatable, Sendable {
        var userChoseSampleData: Bool
        var businessConfigExisted: Bool
        var existingClientCount: Int
        var existingPetCount: Int
        var restorableClientCount: Int
    }

    static func decide(_ inputs: Inputs) -> Decision {
        guard inputs.userChoseSampleData else { return .skip(.notChosen) }
        if inputs.businessConfigExisted || inputs.existingClientCount > 0 || inputs.existingPetCount > 0 {
            return .skip(.salonHasData)
        }
        if inputs.restorableClientCount > 0 { return .skip(.backupFound) }
        return .seed
    }
}
