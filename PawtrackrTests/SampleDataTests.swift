import XCTest
import SwiftData
@testable import Pawtrackr

/// Sample clients are identified only by the fixed UUIDs in `SampleData`.
/// These tests pin what seeding may touch, and that removal deletes the
/// sample rows and what belongs to them, never a real row, whatever its name.
@MainActor
final class SampleDataTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let schema = Schema(PawtrackrSchema.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [config])
        context = container.mainContext
        suiteName = "SampleDataTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        container = nil
        context = nil
        try super.tearDownWithError()
    }

    // MARK: - Seeding

    func testSeedingUsesTheFixedSampleUUIDs() throws {
        XCTAssertTrue(try DemoDataSeeder.seedIfNeeded(in: context, userDefaults: defaults))

        XCTAssertEqual(Set(try context.fetch(FetchDescriptor<Client>()).map(\.uuid)), SampleData.clientIDs)
        XCTAssertEqual(Set(try context.fetch(FetchDescriptor<Pet>()).map(\.uuid)), SampleData.petIDs)
        let visits = try context.fetch(FetchDescriptor<Visit>())
        XCTAssertEqual(Set(visits.map(\.uuid)), SampleData.visitIDs)

        // The pet's fixed UUID was in place before its visits were created.
        let active = try XCTUnwrap(visits.first { $0.uuid == SampleData.miloActiveVisitID })
        XCTAssertNil(active.endedAt)
        XCTAssertEqual(active.pet?.uuid, SampleData.miloPetID)
        XCTAssertEqual(active.sessionToken, Visit.makeSessionToken(petUUID: SampleData.miloPetID, startedAt: active.startedAt))

        XCTAssertEqual(try SampleData.sampleClientCount(in: context), 2)
        XCTAssertEqual(try SampleData.realClientCount(in: context), 0)
        XCTAssertEqual(SampleData.tourClient(in: context)?.uuid, SampleData.avaClientID,
                       "The tour opens the sample client whose pet is checked in.")
    }

    func testSeederChangesNothingInAStoreThatHasClients() throws {
        DataMigrations.ensureServiceCatalog(in: context)
        try service(named: "Bath").setBasePrice(80)
        try service(named: "Haircut").setEnabled(false)
        context.insert(Client(firstName: "Rosa", lastName: "Diaz"))
        try context.save()
        let before = try serviceSnapshot()

        XCTAssertFalse(try DemoDataSeeder.seedIfNeeded(in: context, userDefaults: defaults))

        XCTAssertEqual(try serviceSnapshot(), before, "Prices, the enabled switch and change stamps stay as they were.")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Client>()), 1)
        XCTAssertEqual(try SampleData.sampleClientCount(in: context), 0)
    }

    func testSeederChangesNothingWhenOnlyPetsExist() throws {
        context.insert(Pet(name: "Orphan", species: .cat))
        try context.save()

        XCTAssertFalse(try DemoDataSeeder.seedIfNeeded(in: context, userDefaults: defaults))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Client>()), 0)
    }

    func testSeederPricesOnlyUnpricedCatalogServicesAndNeverChangesEnabled() throws {
        DataMigrations.ensureServiceCatalog(in: context)
        try service(named: "Bath").setBasePrice(80)
        try service(named: "Haircut").setEnabled(false)
        context.insert(Service(name: "Teeth Brushing", category: .addOn))
        try context.save()

        XCTAssertTrue(try DemoDataSeeder.seedIfNeeded(in: context, userDefaults: defaults))

        XCTAssertEqual(try service(named: "Bath").basePrice, 80, "A price the salon set is kept.")
        XCTAssertFalse(try service(named: "Haircut").isEnabled, "A service the salon turned off stays off.")
        XCTAssertNil(try service(named: "Teeth Brushing").basePrice, "Custom services get no invented price.")
        XCTAssertEqual(try service(named: "Full Package").basePrice, 95)
    }

    // MARK: - Removal

    func testRemovingSampleDataLeavesRealRowsUntouched() throws {
        XCTAssertTrue(try DemoDataSeeder.seedIfNeeded(in: context, userDefaults: defaults))
        let sharedDay = try XCTUnwrap(try visit(SampleData.miloRecentVisitID).endedAt)

        // A real client who shares the sample's name, with a visit on the
        // same day as a sample visit.
        let realAva = Client(firstName: "Ava", lastName: "Martinez", phone: "3125550110")
        let realMilo = Pet(name: "Milo", species: .dog)
        realMilo.owner = realAva
        realAva.pets = [realMilo]
        context.insert(realAva)
        context.insert(realMilo)
        let realVisit = Visit(pet: realMilo, startedAt: sharedDay.addingTimeInterval(-3600))
        context.insert(realVisit)
        realMilo.visits = [realVisit]
        let realPayment = Payment(amount: 70, method: .cash, paidAt: sharedDay)
        context.insert(realPayment)
        realVisit.attachPayment(realPayment)
        realVisit.markCheckedOut(total: 70, now: sharedDay)

        context.insert(LoyaltyLedgerEntry(kind: .earned, points: 70, clientUUID: realAva.uuid, visitUUID: realVisit.uuid))
        context.insert(LoyaltyLedgerEntry(kind: .earned, points: 95, clientUUID: SampleData.avaClientID, visitUUID: SampleData.miloRecentVisitID))
        context.insert(CheckoutTransaction(
            idempotencyKey: "checkout:\(realVisit.uuid.uuidString)", visitUUID: realVisit.uuid, petUUID: realMilo.uuid,
            clientUUID: realAva.uuid, amount: 70, method: .cash, externalReference: nil
        ))
        context.insert(CheckoutTransaction(
            idempotencyKey: "checkout:\(SampleData.miloActiveVisitID.uuidString)", visitUUID: SampleData.miloActiveVisitID,
            petUUID: SampleData.miloPetID, clientUUID: SampleData.avaClientID, amount: 50, method: .cash, externalReference: nil
        ))

        // A second device loaded the samples too: same UUIDs, separate rows.
        let otherAva = Client(firstName: "Ava", lastName: "Martinez")
        otherAva.uuid = SampleData.avaClientID
        let otherMilo = Pet(name: "Milo", species: .dog)
        otherMilo.uuid = SampleData.miloPetID
        otherMilo.owner = otherAva
        otherAva.pets = [otherMilo]
        context.insert(otherAva)
        context.insert(otherMilo)
        let otherVisit = Visit(pet: otherMilo, startedAt: .now.addingTimeInterval(-600))
        otherVisit.uuid = SampleData.miloActiveVisitID
        context.insert(otherVisit)
        otherMilo.visits = [otherVisit]
        try context.save()
        SummaryUpdater.rebuildDay(for: sharedDay, in: context)
        try context.save()

        let result = try DataReset.removeSampleData(in: context, userDefaults: defaults)

        XCTAssertEqual(result.clients, 3, "Both copies of Ava and Jordan go.")
        XCTAssertEqual(try SampleData.sampleClientCount(in: context), 0)
        for id in SampleData.petIDList {
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<Pet>(predicate: #Predicate { $0.uuid == id })), 0)
        }
        for id in SampleData.visitIDList {
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<Visit>(predicate: #Predicate { $0.uuid == id })), 0)
        }

        let clients = try context.fetch(FetchDescriptor<Client>())
        XCTAssertEqual(clients.map(\.uuid), [realAva.uuid])
        XCTAssertEqual(clients.first?.fullName, "Ava Martinez", "Nothing is matched by name.")
        XCTAssertEqual(try context.fetch(FetchDescriptor<Pet>()).map(\.uuid), [realMilo.uuid])
        let visits = try context.fetch(FetchDescriptor<Visit>())
        XCTAssertEqual(visits.map(\.uuid), [realVisit.uuid])
        XCTAssertEqual(visits.first?.total, 70)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Payment>()), 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LoyaltyLedgerEntry>()).map(\.clientUUID), [realAva.uuid])
        XCTAssertEqual(try context.fetch(FetchDescriptor<CheckoutTransaction>()).map(\.visitUUID), [realVisit.uuid])

        let day = Calendar.current.startOfDay(for: sharedDay)
        let summaries = try context.fetch(FetchDescriptor<DaySummary>()).filter { $0.day == day }
        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(summaries.first?.revenue, 70, "The shared day now counts only the real visit.")
        XCTAssertEqual(summaries.first?.visitCount, 1)
    }

    func testConfirmationListsPetsAddedUnderSampleClientsBeforeRemovingThem() throws {
        XCTAssertTrue(try DemoDataSeeder.seedIfNeeded(in: context, userDefaults: defaults))
        let ava = try XCTUnwrap(try SampleData.sampleClients(in: context).first { $0.uuid == SampleData.avaClientID })
        let biscuit = Pet(name: "Biscuit", species: .cat)
        biscuit.owner = ava
        context.insert(biscuit)
        ava.pets = (ava.pets ?? []) + [biscuit]
        try context.save()

        let inventory = try DataReset.sampleDataInventory(in: context, userDefaults: defaults)
        XCTAssertEqual(Set(inventory.clientNames), ["Ava Martinez", "Jordan Lee"])
        XCTAssertEqual(inventory.addedPetNames, ["Biscuit"])
        XCTAssertTrue(SampleDataCopy.removeMessage(for: inventory).contains("Biscuit"),
                      "The confirmation names the added pet before it is deleted.")

        try DataReset.removeSampleData(in: context, userDefaults: defaults)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Pet>()), 0)
        XCTAssertTrue(try DataReset.sampleDataInventory(in: context, userDefaults: defaults).isEmpty)
    }

    // MARK: - Example prices

    func testRemovalClearsOnlyTheExamplePricesNobodyChanged() throws {
        DataMigrations.ensureServiceCatalog(in: context)
        try service(named: "Bath").setBasePrice(80)
        try context.save()

        XCTAssertTrue(try DemoDataSeeder.seedIfNeeded(in: context, userDefaults: defaults))
        XCTAssertEqual(try service(named: "Full Package").basePrice, 95)
        XCTAssertEqual(try service(named: "Haircut").basePrice, 60)
        XCTAssertEqual(try service(named: "De-shedding").basePrice, 24)

        // Later edits: a new price, and the same price saved again. Either
        // way the service now holds a price someone chose.
        Thread.sleep(forTimeInterval: 0.01)
        try service(named: "Haircut").setBasePrice(65)
        try service(named: "De-shedding").setBasePrice(24)
        try context.save()

        let inventory = try DataReset.sampleDataInventory(in: context, userDefaults: defaults)
        XCTAssertGreaterThan(inventory.examplePriceCount, 0)
        let priceSentence = AppLocalization.localized("sample_data.remove.example_prices", value: "")
        XCTAssertFalse(priceSentence.isEmpty)
        XCTAssertTrue(SampleDataCopy.removeMessage(for: inventory).contains(priceSentence),
                      "The confirmation says example prices go too.")
        XCTAssertFalse(SampleDataCopy.removeMessage(for: SampleDataInventory(clientNames: ["Ava Martinez"], addedPetNames: []))
            .contains(priceSentence), "No price sentence when there is nothing to take back.")

        let result = try DataReset.removeSampleData(in: context, userDefaults: defaults)

        XCTAssertEqual(result.examplePricesCleared, inventory.examplePriceCount)
        XCTAssertNil(try service(named: "Full Package").basePrice, "An untouched example price is taken back.")
        XCTAssertEqual(try service(named: "Bath").basePrice, 80, "A price set before the samples stays.")
        XCTAssertEqual(try service(named: "Haircut").basePrice, 65, "A price changed since stays.")
        XCTAssertEqual(try service(named: "De-shedding").basePrice, 24, "A price saved again since stays.")
        XCTAssertNil(defaults.dictionary(forKey: SamplePriceRecord.userDefaultsKey), "The record is spent.")

        // Nothing left to take back: a second pass changes nothing.
        XCTAssertEqual(try DataReset.removeSampleData(in: context, userDefaults: defaults).examplePricesCleared, 0)
        XCTAssertFalse(context.hasChanges)
    }

    func testRemovalOnADeviceThatDidNotLoadTheSamplesKeepsEveryPrice() throws {
        XCTAssertTrue(try DemoDataSeeder.seedIfNeeded(in: context, userDefaults: defaults))
        let before = try serviceSnapshot()

        let otherSuite = "SampleDataTests.other.\(UUID().uuidString)"
        let otherDevice = try XCTUnwrap(UserDefaults(suiteName: otherSuite))
        defer { otherDevice.removePersistentDomain(forName: otherSuite) }

        XCTAssertEqual(try DataReset.sampleDataInventory(in: context, userDefaults: otherDevice).examplePriceCount, 0)
        let result = try DataReset.removeSampleData(in: context, userDefaults: otherDevice)

        XCTAssertEqual(result.examplePricesCleared, 0)
        XCTAssertEqual(try service(named: "Full Package").basePrice, 95)
        XCTAssertEqual(try serviceSnapshot(), before, "Without proof a price is still the example one, it stays.")
    }

    func testSampleClientsNeverCountTowardTheDataLossBaseline() throws {
        let appSupport = try makeAppSupportDirectory()
        defer { try? FileManager.default.removeItem(at: appSupport) }

        XCTAssertTrue(try DemoDataSeeder.seedIfNeeded(in: context, userDefaults: defaults))
        DataSafetyMonitor.evaluateClientStoreState(in: context, appSupportURL: appSupport, userDefaults: defaults)
        XCTAssertEqual(defaults.integer(forKey: DataSafetyMonitor.lastKnownClientCountKey), 0,
                       "Only real clients count.")

        // The samples disappear the way another device's removal arrives
        // through iCloud: plain deletes, no removeSampleData bookkeeping here.
        for client in try SampleData.sampleClients(in: context) {
            context.delete(client)
        }
        try context.save()
        DataSafetyMonitor.evaluateClientStoreState(in: context, appSupportURL: appSupport, userDefaults: defaults)

        XCTAssertFalse(defaults.bool(forKey: DataSafetyMonitor.suspectedDataLossKey),
                       "Losing sample clients is never data loss.")
    }

    func testLosingRealClientsIsStillFlaggedWhileSamplesRemain() throws {
        let appSupport = try makeAppSupportDirectory()
        defer { try? FileManager.default.removeItem(at: appSupport) }

        XCTAssertTrue(try DemoDataSeeder.seedIfNeeded(in: context, userDefaults: defaults))
        let real = (1...3).map { Client(firstName: "Real \($0)", lastName: "Client") }
        real.forEach(context.insert)
        try context.save()
        DataSafetyMonitor.evaluateClientStoreState(in: context, appSupportURL: appSupport, userDefaults: defaults)
        XCTAssertEqual(defaults.integer(forKey: DataSafetyMonitor.lastKnownClientCountKey), 3)

        real.forEach(context.delete)
        try context.save()
        DataSafetyMonitor.evaluateClientStoreState(in: context, appSupportURL: appSupport, userDefaults: defaults)

        XCTAssertTrue(defaults.bool(forKey: DataSafetyMonitor.suspectedDataLossKey),
                      "The two sample clients left behind don't hide that every real client is gone.")
    }

    func testBackupsNeverOfferSampleClientsBack() {
        let samplesOnly = StoreBackupRestore.Candidate(
            directoryName: "PreUpdateBackup-test", kind: .preUpdate, createdAt: .now,
            clientCount: 2, clientUUIDs: SampleData.clientIDs
        )
        XCTAssertEqual(samplesOnly.missingClientCount(liveClientUUIDs: []), 0)
        XCTAssertNil(StoreBackupRestore.offer(from: [samplesOnly], liveClientUUIDs: [], dismissed: []))

        let mixed = StoreBackupRestore.Candidate(
            directoryName: "PreUpdateBackup-test2", kind: .preUpdate, createdAt: .now,
            clientCount: 3, clientUUIDs: SampleData.clientIDs.union([UUID()])
        )
        XCTAssertEqual(mixed.missingClientCount(liveClientUUIDs: []), 1, "Real clients in a backup still count.")
    }

    // MARK: - Seed policy

    func testSeedPolicyOnlySeedsAProvablyEmptySalon() {
        let empty = SampleDataSeedPolicy.Inputs(
            userChoseSampleData: true, businessConfigExisted: false,
            existingClientCount: 0, existingPetCount: 0, iCloud: .settled, restorableClientCount: 0
        )
        XCTAssertEqual(SampleDataSeedPolicy.decide(empty), .seed)

        var inputs = empty
        inputs.iCloud = .off
        XCTAssertEqual(SampleDataSeedPolicy.decide(inputs), .seed)

        inputs = empty
        inputs.userChoseSampleData = false
        XCTAssertEqual(SampleDataSeedPolicy.decide(inputs), .skip(.notChosen))

        inputs = empty
        inputs.businessConfigExisted = true
        XCTAssertEqual(SampleDataSeedPolicy.decide(inputs), .skip(.salonHasData))

        inputs = empty
        inputs.existingClientCount = 1
        XCTAssertEqual(SampleDataSeedPolicy.decide(inputs), .skip(.salonHasData))

        inputs = empty
        inputs.existingPetCount = 1
        XCTAssertEqual(SampleDataSeedPolicy.decide(inputs), .skip(.salonHasData))

        inputs = empty
        inputs.restorableClientCount = 3
        XCTAssertEqual(SampleDataSeedPolicy.decide(inputs), .skip(.backupFound))

        inputs = empty
        inputs.iCloud = .stillChecking
        XCTAssertEqual(SampleDataSeedPolicy.decide(inputs), .skip(.iCloudStillChecking))
    }

    // MARK: - Helpers

    private struct ServiceState: Equatable {
        let price: Decimal?
        let isEnabled: Bool
        let updatedAt: Date
        let lastModifiedBy: UUID
    }

    private func serviceSnapshot() throws -> [UUID: ServiceState] {
        Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<Service>()).map {
            ($0.uuid, ServiceState(price: $0.basePrice, isEnabled: $0.isEnabled, updatedAt: $0.updatedAt, lastModifiedBy: $0.lastModifiedBy))
        })
    }

    private func service(named name: String) throws -> Service {
        try XCTUnwrap(try context.fetch(FetchDescriptor<Service>()).first { $0.name == name }, "No service named \(name)")
    }

    private func makeAppSupportDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func visit(_ id: UUID) throws -> Visit {
        try XCTUnwrap(try context.fetch(FetchDescriptor<Visit>(predicate: #Predicate { $0.uuid == id })).first)
    }
}
