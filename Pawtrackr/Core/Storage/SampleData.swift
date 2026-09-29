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
/// Two devices that both loaded samples before syncing hold records with the
/// same UUIDs, so every lookup here returns all matches, never just the first.
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

/// When sample clients may be added. They go into the real, iCloud-mirrored
/// store and upload to every device of the salon, so they may only go into a
/// salon that is provably empty. When in doubt the answer is "skip": the user
/// can still load them later from Settings.
enum SampleDataSeedPolicy {
    enum ICloudState: Equatable, Sendable {
        /// Nothing can download into this store right now: mirroring is off,
        /// or there is no usable iCloud account.
        case off
        /// Mirroring is on and the first iCloud download check has finished.
        case settled
        /// Mirroring is on and iCloud may still be delivering the salon's
        /// records (the account is unknown or the first check hasn't finished).
        case stillChecking
    }

    enum SkipReason: Equatable, Sendable {
        case notChosen
        /// A business profile existed before setup, or clients or pets exist.
        case salonHasData
        /// A backup on this device holds clients the store is missing.
        case backupFound
        case iCloudStillChecking
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
        var iCloud: ICloudState
        var restorableClientCount: Int
    }

    static func decide(_ inputs: Inputs) -> Decision {
        guard inputs.userChoseSampleData else { return .skip(.notChosen) }
        if inputs.businessConfigExisted || inputs.existingClientCount > 0 || inputs.existingPetCount > 0 {
            return .skip(.salonHasData)
        }
        if inputs.restorableClientCount > 0 { return .skip(.backupFound) }
        if inputs.iCloud == .stillChecking { return .skip(.iCloudStillChecking) }
        return .seed
    }

    /// Reads the live iCloud state from the monitor.
    @MainActor
    static func currentICloudState() -> ICloudState {
        currentICloudState(monitor: CloudKitMonitor.shared)
    }

    @MainActor
    static func currentICloudState(monitor: CloudKitMonitor) -> ICloudState {
        guard monitor.mode.isMirroring else { return .off }
        switch monitor.accountState {
        case .available:
            return monitor.firstSyncCompleted ? .settled : .stillChecking
        case .unknown:
            return .stillChecking
        case .noAccount, .restricted, .temporarilyUnavailable, .couldNotDetermine:
            return .off
        }
    }
}
