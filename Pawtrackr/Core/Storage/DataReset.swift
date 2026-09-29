//
//  DataReset.swift
//  Pawtrackr
//
//  "Start Fresh" support. Erases operational business records while preserving
//  the user's setup so a new operator can move from the guided demo into real
//  use with one tap.
//

import Foundation
import SwiftData
import OSLog

/// Erases operational records ("Start Fresh") while preserving setup. The Service
/// catalog, `BusinessConfig`, message templates, and device/sync identity all
/// survive — only the data a user accumulates (clients, pets, visits, payments,
/// inventory, checkout ledger, analytics rollups) is removed.
///
/// This is a *full* operational wipe: every client, real or sample, goes. To
/// remove only the sample clients, use `removeSampleData(in:)`, which finds
/// them by their fixed UUIDs (`SampleData`). Deletions are logical (`context.delete`), which
/// `NSPersistentCloudKitContainer` exports as tombstones — so the wipe
/// propagates to iCloud and every signed-in device. That is intentional, but it
/// is why the calling UI must gate it behind an explicit, destructive
/// confirmation.
@MainActor
enum DataReset {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "DataReset")

    /// Deletes all operational data via the main context. Children are removed
    /// through SwiftData cascade rules (`Client → Pet → Visit → VisitItem/Payment`
    /// and `EmergencyContact`; `InventoryItem → InventoryTransaction`), so only
    /// cascade roots plus the standalone rollup/ledger models are deleted here.
    static func wipeOperationalData(in context: ModelContext) throws {
        try deleteAll(Client.self, in: context)          // cascades pets/visits/items/payments/contacts
        try deleteAll(InventoryItem.self, in: context)   // cascades inventory transactions

        // Standalone models not reached by any cascade.
        try deleteAll(CheckoutTransaction.self, in: context)
        try deleteAll(DaySummary.self, in: context)
        try deleteAll(ServiceDaySummary.self, in: context)
        try deleteAll(CategoryDaySummary.self, in: context)
        try deleteAll(ClientInsightSummary.self, in: context)

        if context.hasChanges {
            try context.save()
        }

        // Every client and pet is gone, so there is nothing to rebuild: remove
        // all items (and any pending or in-flight indexing) so stale results
        // don't linger.
        SpotlightIndexer.shared.removeAllItems()
        log.info("Start Fresh: operational data wiped (catalog + business config preserved).")
    }

    private static func deleteAll<T: PersistentModel>(_ type: T.Type, in context: ModelContext) throws {
        let objects = try context.fetch(FetchDescriptor<T>())
        for object in objects {
            context.delete(object)
        }
    }
}

// MARK: - Sample data

/// What "Remove Sample Clients" will delete, read before asking the user so the
/// confirmation can name every row, including ones added under a sample client.
struct SampleDataInventory: Equatable, Sendable {
    /// Current names of the sample clients (they may have been edited).
    var clientNames: [String]
    /// Pets under sample clients that aren't sample pets: someone added them.
    var addedPetNames: [String]

    var isEmpty: Bool { clientNames.isEmpty }
}

@MainActor
extension DataReset {
    struct SampleRemovalResult: Equatable {
        var clients = 0
        var pets = 0
        var visits = 0
        var ledgerEntries = 0
        var checkoutTransactions = 0
    }

    static func sampleDataInventory(in context: ModelContext) throws -> SampleDataInventory {
        let clients = try SampleData.sampleClients(in: context)
        var names: [String] = []
        var addedPets: [String] = []
        for client in clients {
            let name = client.fullName
            if !names.contains(name) { names.append(name) }
            for pet in client.pets ?? [] where !SampleData.isSample(pet) {
                addedPets.append(pet.name)
            }
        }
        return SampleDataInventory(clientNames: names, addedPetNames: addedPets)
    }

    /// Deletes the sample salon and nothing else. Rows are found only by the
    /// fixed UUIDs in `SampleData`, never by name, so a real client called
    /// "Ava Martinez" is untouched. Every copy of a sample UUID goes (two
    /// devices that both loaded samples each uploaded one), together with the
    /// rows that belong to them:
    /// - pets, visits, line items, payments and emergency contacts (by
    ///   relationship; anything added under a sample client or pet goes too,
    ///   which the confirmation lists first),
    /// - loyalty ledger entries, checkout transactions and client insight
    ///   rows, which point at sample clients, pets or visits by UUID.
    /// Day summaries for the affected days are rebuilt from what remains.
    /// The deletions sync to iCloud like any other delete.
    @discardableResult
    static func removeSampleData(in context: ModelContext, userDefaults: UserDefaults = .standard) throws -> SampleRemovalResult {
        var result = SampleRemovalResult()

        let clients = unique(try SampleData.sampleClients(in: context))

        // Sample pets are found by UUID as well as under sample clients. If
        // one was ever filed under a real owner, that owner stays: only the
        // pet itself (and its visits) is sample data.
        var pets: [Pet] = []
        for id in SampleData.petIDList {
            pets += try context.fetch(FetchDescriptor<Pet>(predicate: #Predicate { $0.uuid == id }))
        }
        for client in clients {
            pets += client.pets ?? []
        }
        pets = unique(pets)

        var visits: [Visit] = []
        for id in SampleData.visitIDList {
            visits += try context.fetch(FetchDescriptor<Visit>(predicate: #Predicate { $0.uuid == id }))
        }
        for pet in pets {
            visits += pet.visits ?? []
        }
        visits = unique(visits)

        let clientUUIDs = Set(clients.map(\.uuid)).union(SampleData.clientIDs)
        let petUUIDs = Set(pets.map(\.uuid)).union(SampleData.petIDs)
        let visitUUIDs = Set(visits.map(\.uuid)).union(SampleData.visitIDs)

        let calendar = Calendar.current
        var affectedDays: Set<Date> = []
        for visit in visits {
            affectedDays.insert(calendar.startOfDay(for: visit.endedAt ?? visit.startedAt))
            if let paidAt = visit.payment?.paidAt {
                affectedDays.insert(calendar.startOfDay(for: paidAt))
            }
        }

        let spotlightRemovals = clients.map { client in
            (client.uuid, (client.pets ?? []).map(\.uuid))
        }

        for visit in visits {
            for item in visit.items ?? [] { context.delete(item) }
            if let payment = visit.payment { context.delete(payment) }
            context.delete(visit)
        }
        for pet in pets { context.delete(pet) }
        for client in clients {
            for contact in client.emergencyContacts ?? [] { context.delete(contact) }
            context.delete(client)
        }
        result.clients = clients.count
        result.pets = pets.count
        result.visits = visits.count

        // Ledger entries and checkout transactions have no relationship to
        // the rows they describe, so nothing cascades to them.
        var ledgerEntries: [LoyaltyLedgerEntry] = []
        for id in clientUUIDs {
            ledgerEntries += try context.fetch(FetchDescriptor<LoyaltyLedgerEntry>(predicate: #Predicate { $0.clientUUID == id }))
        }
        for id in visitUUIDs {
            let optionalID: UUID? = id
            ledgerEntries += try context.fetch(FetchDescriptor<LoyaltyLedgerEntry>(predicate: #Predicate { $0.visitUUID == optionalID }))
        }
        for entry in unique(ledgerEntries) {
            context.delete(entry)
            result.ledgerEntries += 1
        }

        var transactions: [CheckoutTransaction] = []
        for id in visitUUIDs {
            transactions += try context.fetch(FetchDescriptor<CheckoutTransaction>(predicate: #Predicate { $0.visitUUID == id }))
        }
        for id in petUUIDs {
            transactions += try context.fetch(FetchDescriptor<CheckoutTransaction>(predicate: #Predicate { $0.petUUID == id }))
        }
        for id in clientUUIDs {
            let optionalID: UUID? = id
            transactions += try context.fetch(FetchDescriptor<CheckoutTransaction>(predicate: #Predicate { $0.clientUUID == optionalID }))
        }
        for transaction in unique(transactions) {
            context.delete(transaction)
            result.checkoutTransactions += 1
        }

        for id in clientUUIDs {
            let rows = try context.fetch(FetchDescriptor<ClientInsightSummary>(predicate: #Predicate { $0.clientUUID == id }))
            for row in rows { context.delete(row) }
        }

        if context.hasChanges {
            try context.save()
        }

        for day in affectedDays {
            SummaryUpdater.rebuildDay(for: day, in: context)
        }
        if context.hasChanges {
            try context.save()
        }

        for (clientID, petIDs) in spotlightRemovals {
            SpotlightIndexer.shared.removeClientAndPetsFromIndex(clientID: clientID, petIDs: petIDs)
        }
        for pet in pets where !spotlightRemovals.contains(where: { $0.1.contains(pet.uuid) }) {
            SpotlightIndexer.shared.removePetFromIndex(petID: pet.uuid)
        }

        // The client count dropped on purpose. Without this the next launch
        // reads "had 2 clients, now 0" as data loss and locks Start Fresh.
        let remaining = try context.fetchCount(FetchDescriptor<Client>())
        DataSafetyMonitor.recordIntentionalSampleRemoval(remainingClientCount: remaining, userDefaults: userDefaults)

        log.info("Removed sample data: clients=\(result.clients), pets=\(result.pets), visits=\(result.visits), ledger=\(result.ledgerEntries), transactions=\(result.checkoutTransactions)")
        return result
    }

    private static func unique<T: PersistentModel>(_ models: [T]) -> [T] {
        var seen: Set<PersistentIdentifier> = []
        return models.filter { seen.insert($0.persistentModelID).inserted }
    }
}
