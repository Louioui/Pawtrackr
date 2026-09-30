import XCTest
import SwiftData
import CoreSpotlight
@testable import Pawtrackr

/// Records what SpotlightIndexer sends to the index instead of touching the
/// device's Spotlight. Completions run asynchronously, like the real index.
final class RecordingSpotlightIndex: SpotlightIndexWriting, @unchecked Sendable {
    enum Call: Equatable {
        case index([String])
        case delete([String])
        case deleteAll
    }

    private let lock = NSLock()
    private var recordedCalls: [Call] = []
    private var items: [String: CSSearchableItem] = [:]
    private var indexCount = 0

    /// Runs off the indexer's lock, before the completion of the Nth index
    /// call (1-based), so a test can change the policy mid-rebuild.
    var beforeIndexCompletion: (@Sendable (Int) -> Void)?
    /// Runs after every recorded call.
    var onCall: (@Sendable (Call) -> Void)?

    var calls: [Call] { lock.withLock { recordedCalls } }
    var indexedItems: [String: CSSearchableItem] { lock.withLock { items } }
    var indexCalls: [[String]] {
        calls.compactMap { if case .index(let ids) = $0 { return ids } else { return nil } }
    }

    func index(_ newItems: [CSSearchableItem], completion: @escaping @Sendable (Error?) -> Void) {
        let ids = newItems.map(\.uniqueIdentifier)
        let number: Int = lock.withLock {
            recordedCalls.append(.index(ids))
            for item in newItems { items[item.uniqueIdentifier] = item }
            indexCount += 1
            return indexCount
        }
        let hook = beforeIndexCompletion
        let onCall = onCall
        DispatchQueue.global().async {
            hook?(number)
            onCall?(.index(ids))
            completion(nil)
        }
    }

    func delete(identifiers: [String], completion: @escaping @Sendable (Error?) -> Void) {
        lock.withLock {
            recordedCalls.append(.delete(identifiers))
            for id in identifiers { items.removeValue(forKey: id) }
        }
        let onCall = onCall
        DispatchQueue.global().async {
            onCall?(.delete(identifiers))
            completion(nil)
        }
    }

    func deleteAll(completion: @escaping @Sendable (Error?) -> Void) {
        lock.withLock {
            recordedCalls.append(.deleteAll)
            items.removeAll()
        }
        let onCall = onCall
        DispatchQueue.global().async {
            onCall?(.deleteAll)
            completion(nil)
        }
    }
}

final class SpotlightIndexingTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "SpotlightIndexingTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(PawtrackrSchema.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func localizer(_ lproj: String) throws -> SpotlightContentBuilder.Localizer {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: lproj, withExtension: "lproj")
                ?? Bundle(for: SpotlightIndexer.self).url(forResource: lproj, withExtension: "lproj"),
            "\(lproj).lproj is missing from the app bundle"
        )
        let bundle = try XCTUnwrap(Bundle(url: url))
        return { key, value in bundle.localizedString(forKey: key, value: value, table: nil) }
    }

    private func makeIndexer(_ index: RecordingSpotlightIndex, debounce: DispatchTimeInterval = .milliseconds(20)) -> SpotlightIndexer {
        SpotlightIndexer(index: index, defaults: defaults, debounceInterval: debounce)
    }

    private func clientSnapshot(
        first: String = "Ava",
        last: String = "Martinez",
        phone: String? = "+15552345678",
        email: String? = "ava@example.com",
        pets: [String] = ["Milo", "Luna"]
    ) -> SpotlightClientSnapshot {
        SpotlightClientSnapshot(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            firstName: first,
            lastName: last,
            phone: phone,
            email: email,
            petNames: pets
        )
    }

    private func petSnapshot(ownerPhone: String? = "+15552345678", breed: String? = "Golden Retriever", thumbnail: Data? = nil) -> SpotlightPetSnapshot {
        SpotlightPetSnapshot(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            name: "Milo",
            species: .dog,
            gender: .male,
            breed: breed,
            color: "Gold",
            ownerFirstName: "Ava",
            ownerLastName: "Martinez",
            ownerPhone: ownerPhone,
            thumbnailData: thumbnail
        )
    }

    // MARK: - Identifiers (deep links)

    func testIdentifierParsesClientAndPetAndRoundTrips() {
        let uuid = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

        XCTAssertEqual(SpotlightIdentifier("client-\(uuid.uuidString)"), .client(uuid))
        XCTAssertEqual(SpotlightIdentifier("pet-\(uuid.uuidString)"), .pet(uuid))
        XCTAssertEqual(SpotlightIdentifier("pet-\(uuid.uuidString.lowercased())"), .pet(uuid))
        XCTAssertEqual(SpotlightIdentifier.client(uuid).rawValue, "client-\(uuid.uuidString)")
        XCTAssertEqual(SpotlightIdentifier(SpotlightIdentifier.pet(uuid).rawValue), .pet(uuid))
        XCTAssertEqual(SpotlightIdentifier.client(uuid).domainIdentifier, "com.pawtrackr.clients")
        XCTAssertEqual(SpotlightIdentifier.pet(uuid).domainIdentifier, "com.pawtrackr.pets")
    }

    func testIdentifierRejectsAnythingElse() {
        let uuid = UUID().uuidString
        for raw in ["", "client-", "pet-", "client-not-a-uuid", "visit-\(uuid)", "Client-\(uuid)", uuid, "pet-\(uuid)-extra", " client-\(uuid)"] {
            XCTAssertNil(SpotlightIdentifier(raw), "\(raw) must not resolve to a record")
        }
    }

    func testSpotlightDeepLinkHandlerUsesTheSharedParser() throws {
        var root = URL(fileURLWithPath: #filePath)
        while !FileManager.default.fileExists(atPath: root.appendingPathComponent("Pawtrackr.xcodeproj").path) {
            root.deleteLastPathComponent()
            if root.path == "/" { throw XCTSkip("Repository root not found") }
        }
        let app = try String(contentsOf: root.appendingPathComponent("Pawtrackr/App/PawtrackrApp.swift"), encoding: .utf8)
        XCTAssertTrue(app.contains("SpotlightIdentifier(rawIdentifier)"), "The CSSearchableItemActionType handler must parse ids with SpotlightIdentifier.")
        XCTAssertTrue(app.contains("case .client(let uuid):") && app.contains("case .pet(let uuid):"), "Both client and pet results must navigate.")
    }

    // MARK: - Client content

    func testClientContentHasPhoneNumbersDigitKeywordsAndDescription() throws {
        let content = SpotlightContentBuilder.clientContent(clientSnapshot(), localized: try localizer("en"))

        XCTAssertEqual(content.identifier, .client(UUID(uuidString: "11111111-1111-1111-1111-111111111111")!))
        XCTAssertEqual(content.title, "Ava Martinez")
        XCTAssertEqual(content.description, "Client · 2 pets · (555) 234-5678")
        XCTAssertEqual(content.phoneNumbers, ["+15552345678", "(555) 234-5678"])
        for keyword in ["+15552345678", "(555) 234-5678", "15552345678", "5552345678", "5678", "ava@example.com", "Ava", "Martinez", "Ava Martinez", "Milo", "Luna"] {
            XCTAssertTrue(content.keywords.contains(keyword), "missing keyword \(keyword)")
        }
        XCTAssertEqual(content.keywords.count, Set(content.keywords.map { $0.lowercased() }).count, "keywords are de-duplicated")
    }

    func testClientDescriptionPluralsAndEmailFallback() throws {
        let en = try localizer("en")
        XCTAssertEqual(SpotlightContentBuilder.clientContent(clientSnapshot(pets: ["Milo"]), localized: en).description, "Client · 1 pet · (555) 234-5678")
        XCTAssertEqual(SpotlightContentBuilder.clientContent(clientSnapshot(phone: nil, pets: []), localized: en).description, "Client · No pets · ava@example.com")
        XCTAssertEqual(SpotlightContentBuilder.clientContent(clientSnapshot(phone: nil, email: nil, pets: []), localized: en).description, "Client · No pets")
    }

    func testClientDescriptionIsLocalizedInSpanish() throws {
        for lproj in ["es", "es-419"] {
            let es = try localizer(lproj)
            XCTAssertEqual(SpotlightContentBuilder.clientContent(clientSnapshot(), localized: es).description, "Cliente · 2 mascotas · (555) 234-5678", lproj)
            XCTAssertEqual(SpotlightContentBuilder.clientContent(clientSnapshot(pets: ["Milo"]), localized: es).description, "Cliente · 1 mascota · (555) 234-5678", lproj)
            XCTAssertEqual(SpotlightContentBuilder.clientContent(clientSnapshot(phone: nil, email: nil, pets: []), localized: es).description, "Cliente · Sin mascotas", lproj)
            XCTAssertEqual(SpotlightContentBuilder.clientContent(clientSnapshot(first: " ", last: ""), localized: es).title, "Cliente sin nombre", lproj)
        }
    }

    func testClientWithUnreadablePhoneKeepsItAsTyped() throws {
        let content = SpotlightContentBuilder.clientContent(clientSnapshot(phone: "020 7946 0958"), localized: try localizer("en"))

        XCTAssertEqual(content.phoneNumbers, ["020 7946 0958"])
        XCTAssertEqual(content.description, "Client · 2 pets · 020 7946 0958")
        XCTAssertTrue(content.keywords.contains("02079460958"))
        XCTAssertTrue(content.keywords.contains("0958"))
    }

    func testPhoneKeywordsForShortNumbersSkipLastFour() {
        XCTAssertEqual(SpotlightContentBuilder.phoneKeywords(for: "12345"), ["12345"])
        XCTAssertEqual(SpotlightContentBuilder.phoneKeywords(for: "   "), [])
        XCTAssertEqual(SpotlightContentBuilder.phoneNumbers(for: ""), [])
    }

    func testSearchableItemCarriesPhonesKeywordsAndIdentity() throws {
        let content = SpotlightContentBuilder.clientContent(clientSnapshot(), localized: try localizer("en"))
        let item = SpotlightContentBuilder.searchableItem(for: content)

        XCTAssertEqual(item.uniqueIdentifier, "client-11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(item.domainIdentifier, "com.pawtrackr.clients")
        XCTAssertEqual(item.attributeSet.title, "Ava Martinez")
        XCTAssertEqual(item.attributeSet.contentDescription, "Client · 2 pets · (555) 234-5678")
        XCTAssertEqual(item.attributeSet.phoneNumbers, ["+15552345678", "(555) 234-5678"])
        XCTAssertTrue(item.attributeSet.keywords?.contains("5552345678") == true)
        XCTAssertEqual(item.attributeSet.relatedUniqueIdentifier, item.uniqueIdentifier)
    }

    // MARK: - Pet content

    func testPetContentIsFoundByOwnerPhoneDigits() throws {
        let thumbnail = Data([9, 9, 9])
        let content = SpotlightContentBuilder.petContent(petSnapshot(thumbnail: thumbnail), localized: try localizer("en"))

        XCTAssertEqual(content.identifier, .pet(UUID(uuidString: "22222222-2222-2222-2222-222222222222")!))
        XCTAssertEqual(content.title, "Milo")
        XCTAssertEqual(content.description, "Golden Retriever · Dog · Owner: Ava Martinez")
        XCTAssertEqual(content.thumbnailData, thumbnail)
        for keyword in ["5552345678", "15552345678", "+15552345678", "(555) 234-5678", "5678", "Ava Martinez", "Ava", "Martinez", "Milo", "Dog", "Male", "Golden Retriever", "Gold"] {
            XCTAssertTrue(content.keywords.contains(keyword), "missing keyword \(keyword)")
        }
        XCTAssertTrue(content.phoneNumbers.isEmpty, "The owner's phone is a keyword on the pet, not the pet's own number.")
    }

    func testPetDescriptionIsLocalizedAndHandlesMissingOwnerAndBreed() throws {
        for lproj in ["es", "es-419"] {
            XCTAssertEqual(
                SpotlightContentBuilder.petContent(petSnapshot(), localized: try localizer(lproj)).description,
                "Golden Retriever · Perro · Propietario: Ava Martinez",
                lproj
            )
        }
        var orphan = petSnapshot(ownerPhone: nil, breed: nil)
        orphan.ownerFirstName = nil
        orphan.ownerLastName = nil
        let content = SpotlightContentBuilder.petContent(orphan, localized: try localizer("en"))
        XCTAssertEqual(content.description, "Dog")
        XCTAssertFalse(content.keywords.contains("5678"))
    }

    // MARK: - Privacy policy and plan

    func testPrivacyPolicyBlocksIndexingOnlyWhenTheLockReallyEngages() {
        XCTAssertTrue(SpotlightPrivacyPolicy.allowsIndexing(isLockEnabled: false, isPINSet: false))
        XCTAssertTrue(SpotlightPrivacyPolicy.allowsIndexing(isLockEnabled: false, isPINSet: true))
        XCTAssertTrue(SpotlightPrivacyPolicy.allowsIndexing(isLockEnabled: true, isPINSet: false), "Lock on with no PIN opens without one, so it protects nothing.")
        XCTAssertFalse(SpotlightPrivacyPolicy.allowsIndexing(isLockEnabled: true, isPINSet: true))
    }

    func testPolicyChangePlan() {
        // Lock comes on.
        XCTAssertEqual(SpotlightIndexPlan.onPolicyChange(previous: true, current: false, stored: .built(format: 2)), .removeAll)
        XCTAssertEqual(SpotlightIndexPlan.onPolicyChange(previous: true, current: false, stored: .cleared), .removeAll)
        // First publish of a launch with the lock on: remove unless already cleared.
        XCTAssertEqual(SpotlightIndexPlan.onPolicyChange(previous: nil, current: false, stored: nil), .removeAll)
        XCTAssertEqual(SpotlightIndexPlan.onPolicyChange(previous: nil, current: false, stored: .built(format: 1)), .removeAll)
        XCTAssertEqual(SpotlightIndexPlan.onPolicyChange(previous: nil, current: false, stored: .cleared), .none)
        // Same value again.
        XCTAssertEqual(SpotlightIndexPlan.onPolicyChange(previous: false, current: false, stored: nil), .none)
        XCTAssertEqual(SpotlightIndexPlan.onPolicyChange(previous: true, current: true, stored: nil), .none)
        // Lock goes off while running: rebuild. At launch the launch check decides.
        XCTAssertEqual(SpotlightIndexPlan.onPolicyChange(previous: false, current: true, stored: .cleared), .rebuild)
        XCTAssertEqual(SpotlightIndexPlan.onPolicyChange(previous: nil, current: true, stored: .cleared), .none)
    }

    func testLaunchPlan() {
        let current = SpotlightIndexPlan.currentFormat
        XCTAssertEqual(SpotlightIndexPlan.atLaunch(allowsIndexing: true, stored: nil), .rebuild)
        XCTAssertEqual(SpotlightIndexPlan.atLaunch(allowsIndexing: true, stored: .cleared), .rebuild)
        XCTAssertEqual(SpotlightIndexPlan.atLaunch(allowsIndexing: true, stored: .built(format: current - 1)), .rebuild)
        XCTAssertEqual(SpotlightIndexPlan.atLaunch(allowsIndexing: true, stored: .built(format: current)), .none)
        XCTAssertEqual(SpotlightIndexPlan.atLaunch(allowsIndexing: false, stored: .built(format: current)), .removeAll)
        XCTAssertEqual(SpotlightIndexPlan.atLaunch(allowsIndexing: false, stored: nil), .removeAll)
        XCTAssertEqual(SpotlightIndexPlan.atLaunch(allowsIndexing: false, stored: .cleared), .none)
    }

    func testIndexStateRoundTrips() {
        for state in [SpotlightIndexState.cleared, .built(format: 2), .built(format: 17)] {
            XCTAssertEqual(SpotlightIndexState(storedValue: state.storedValue), state)
        }
        XCTAssertNil(SpotlightIndexState(storedValue: nil))
        XCTAssertNil(SpotlightIndexState(storedValue: "built."))
        XCTAssertNil(SpotlightIndexState(storedValue: "whatever"))
    }

    // MARK: - Indexer: rebuild

    @MainActor
    func testRebuildDeletesFirstThenIndexesEveryRecordInBoundedBatches() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        var clients: [Client] = []
        var pets: [Pet] = []
        for i in 0..<5 {
            let client = Client(firstName: "Owner\(i)", lastName: "Test", phone: "+1555234567\(i)")
            let pet = Pet(name: "Pet\(i)", species: .dog)
            pet.owner = client
            context.insert(client)
            context.insert(pet)
            clients.append(client)
            pets.append(pet)
        }
        try context.save()

        let index = RecordingSpotlightIndex()
        let indexer = makeIndexer(index)
        indexer.applyPrivacyPolicy(allowsIndexing: true)

        let outcome = await indexer.reindexAll(container: container, batchSize: 2)

        XCTAssertEqual(outcome, .completed(clients: 5, pets: 5))
        XCTAssertEqual(index.calls.first, .deleteAll)
        XCTAssertEqual(index.calls.filter { $0 == .deleteAll }.count, 1)
        XCTAssertTrue(index.indexCalls.allSatisfy { $0.count <= 2 }, "batches: \(index.indexCalls.map(\.count))")
        let expected = Set(clients.map { "client-\($0.uuid.uuidString)" } + pets.map { "pet-\($0.uuid.uuidString)" })
        XCTAssertEqual(Set(index.indexedItems.keys), expected)

        let petItem = try XCTUnwrap(index.indexedItems["pet-\(pets[3].uuid.uuidString)"])
        XCTAssertTrue(petItem.attributeSet.keywords?.contains("5552345673") == true, "The pet is found by its owner's phone digits.")
        let clientItem = try XCTUnwrap(index.indexedItems["client-\(clients[3].uuid.uuidString)"])
        XCTAssertEqual(clientItem.attributeSet.phoneNumbers?.first, "+15552345673")
        XCTAssertEqual(indexer.storedIndexState, .built(format: SpotlightIndexPlan.currentFormat))
    }

    @MainActor
    func testRebuildDoesNothingWhileTheLockForbidsIndexing() async throws {
        let container = try makeContainer()
        container.mainContext.insert(Client(firstName: "Ava", lastName: "Martinez", phone: "+15552345678"))
        try container.mainContext.save()

        let unpublished = RecordingSpotlightIndex()
        let unpublishedOutcome = await makeIndexer(unpublished).reindexAll(container: container)
        XCTAssertEqual(unpublishedOutcome, .skippedByPolicy, "Before AppSettings publishes the policy the indexer fails closed.")
        XCTAssertTrue(unpublished.calls.isEmpty)

        let locked = RecordingSpotlightIndex()
        let indexer = makeIndexer(locked)
        indexer.applyPrivacyPolicy(allowsIndexing: false)
        let lockedOutcome = await indexer.reindexAll(container: container)
        XCTAssertEqual(lockedOutcome, .skippedByPolicy)
        XCTAssertEqual(locked.calls, [.deleteAll], "Turning the policy on removes items; the rebuild adds none.")
    }

    @MainActor
    func testLockTurnedOnMidRebuildStopsItAndLeavesTheIndexEmpty() async throws {
        let container = try makeContainer()
        for i in 0..<6 {
            container.mainContext.insert(Client(firstName: "Owner\(i)", lastName: "Test", phone: "+1555234567\(i)"))
        }
        try container.mainContext.save()

        let index = RecordingSpotlightIndex()
        let indexer = makeIndexer(index)
        indexer.applyPrivacyPolicy(allowsIndexing: true)
        index.beforeIndexCompletion = { [weak indexer] number in
            if number == 1 { indexer?.applyPrivacyPolicy(allowsIndexing: false) }
        }

        let outcome = await indexer.reindexAll(container: container, batchSize: 2)

        XCTAssertEqual(outcome, .cancelled)
        XCTAssertEqual(index.indexCalls.count, 1, "No batch is submitted after App Lock comes on.")
        XCTAssertEqual(index.calls.last, .deleteAll, "The privacy removal is the last thing sent to the index.")
        XCTAssertTrue(index.indexedItems.isEmpty)
        XCTAssertEqual(indexer.storedIndexState, .cleared)
    }

    // MARK: - Indexer: live edits and policy transitions

    /// The Academy's practice salon: its clients never reach system search,
    /// nor do records still being built while it is open. Real edits made
    /// meanwhile (another window) are indexed as usual.
    @MainActor
    func testPracticeSalonRecordsAreNeverIndexed() async throws {
        let practice = try makeContainer()
        let real = try makeContainer()
        let practiceClient = Client(firstName: "Ava", lastName: "Practice")
        practice.mainContext.insert(practiceClient)
        let realClient = Client(firstName: "Rosa", lastName: "Real")
        real.mainContext.insert(realClient)
        let unsaved = Client(firstName: "Typed", lastName: "Unsaved")

        let index = RecordingSpotlightIndex()
        let indexer = makeIndexer(index)
        indexer.applyPrivacyPolicy(allowsIndexing: true)
        indexer.beginPracticeSalon(practice)
        indexer.scheduleIndex(client: practiceClient)
        indexer.scheduleIndex(client: unsaved)
        indexer.scheduleIndex(client: realClient, includingPets: true)
        try await Task.sleep(for: .milliseconds(300))

        let indexed = Set(index.indexCalls.flatMap { $0 })
        XCTAssertTrue(indexed.contains("client-\(realClient.uuid.uuidString)"), "Real edits are indexed as usual.")
        XCTAssertFalse(indexed.contains("client-\(practiceClient.uuid.uuidString)"), "Practice clients stay out of Spotlight.")
        XCTAssertFalse(indexed.contains("client-\(unsaved.uuid.uuidString)"), "A record being built is indexed once saved, never from its setters.")

        indexer.endPracticeSalon(practice)
        indexer.scheduleIndex(client: unsaved)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(
            Set(index.indexCalls.flatMap { $0 }).contains("client-\(unsaved.uuid.uuidString)"),
            "With no practice salon open, edits index as before."
        )
    }

    @MainActor
    func testScheduledEditIsIndexedOnlyWhenAllowed() async throws {
        let container = try makeContainer()
        let client = Client(firstName: "Ava", lastName: "Martinez", phone: "+15552345678")
        container.mainContext.insert(client)

        let locked = RecordingSpotlightIndex()
        let lockedIndexer = makeIndexer(locked)
        lockedIndexer.applyPrivacyPolicy(allowsIndexing: false)
        lockedIndexer.scheduleIndex(client: client)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(locked.calls, [.deleteAll], "With App Lock on, an edit indexes nothing.")

        let open = RecordingSpotlightIndex()
        let indexed = expectation(description: "client indexed")
        indexed.assertForOverFulfill = false
        open.onCall = { call in if case .index = call { indexed.fulfill() } }
        let openIndexer = makeIndexer(open)
        openIndexer.applyPrivacyPolicy(allowsIndexing: true)
        openIndexer.scheduleIndex(client: client)
        await fulfillment(of: [indexed], timeout: 3)

        let item = try XCTUnwrap(open.indexedItems["client-\(client.uuid.uuidString)"])
        XCTAssertTrue(item.attributeSet.keywords?.contains("5552345678") == true, "Live edits carry the phone keywords too.")
        XCTAssertEqual(item.attributeSet.phoneNumbers, ["+15552345678", "(555) 234-5678"])
    }

    @MainActor
    func testClientEditReindexesItsPetsWithTheNewOwnerPhone() async throws {
        let container = try makeContainer()
        let client = Client(firstName: "Ava", lastName: "Martinez")
        let pet = Pet(name: "Milo", species: .dog)
        pet.owner = client
        container.mainContext.insert(client)
        container.mainContext.insert(pet)
        try container.mainContext.save()
        client.setPhone("555-987-6543")

        let index = RecordingSpotlightIndex()
        let indexed = expectation(description: "client and pet indexed")
        indexed.assertForOverFulfill = false
        index.onCall = { call in if case .index = call { indexed.fulfill() } }
        let indexer = makeIndexer(index)
        indexer.applyPrivacyPolicy(allowsIndexing: true)
        indexer.scheduleIndex(client: client, includingPets: true)
        await fulfillment(of: [indexed], timeout: 3)

        let petItem = try XCTUnwrap(index.indexedItems["pet-\(pet.uuid.uuidString)"])
        XCTAssertTrue(petItem.attributeSet.keywords?.contains("5559876543") == true)
        XCTAssertEqual(petItem.attributeSet.contentDescription?.hasSuffix("Ava Martinez"), true)
    }

    func testLockOnRemovesOnceAndLockOffRebuilds() async throws {
        let container = try makeContainer()
        await MainActor.run {
            container.mainContext.insert(Client(firstName: "Ava", lastName: "Martinez", phone: "+15552345678"))
            try? container.mainContext.save()
        }

        let index = RecordingSpotlightIndex()
        let indexer = makeIndexer(index)
        indexer.attach(container: container)

        XCTAssertEqual(indexer.applyPrivacyPolicy(allowsIndexing: true), .none, "The first publish leaves rebuilding to the launch check.")
        XCTAssertEqual(indexer.applyPrivacyPolicy(allowsIndexing: false), .removeAll)
        XCTAssertEqual(indexer.storedIndexState, .cleared)
        XCTAssertEqual(indexer.applyPrivacyPolicy(allowsIndexing: false), .none)
        XCTAssertEqual(index.calls, [.deleteAll])

        let rebuilt = expectation(description: "rebuilt after the lock went off")
        rebuilt.assertForOverFulfill = false
        index.onCall = { call in if case .index = call { rebuilt.fulfill() } }
        XCTAssertEqual(indexer.applyPrivacyPolicy(allowsIndexing: true), .rebuild)
        await fulfillment(of: [rebuilt], timeout: 5)
        XCTAssertEqual(index.indexedItems.count, 1)
    }

    func testLaunchCheckRebuildsOnceAndThenLeavesTheIndexAlone() async throws {
        let container = try makeContainer()
        await MainActor.run {
            container.mainContext.insert(Client(firstName: "Ava", lastName: "Martinez", phone: "+15552345678"))
            try? container.mainContext.save()
        }

        let index = RecordingSpotlightIndex()
        let indexer = makeIndexer(index)
        let unpublished = await indexer.reconcileAtLaunch(container: container)
        XCTAssertEqual(unpublished, .none, "No policy yet: do nothing rather than guess.")

        indexer.applyPrivacyPolicy(allowsIndexing: true)
        let first = await indexer.reconcileAtLaunch(container: container)
        XCTAssertEqual(first, .rebuild)
        XCTAssertEqual(indexer.storedIndexState, .built(format: SpotlightIndexPlan.currentFormat))
        let callsAfterFirst = index.calls.count
        let second = await indexer.reconcileAtLaunch(container: container)
        XCTAssertEqual(second, .none)
        XCTAssertEqual(index.calls.count, callsAfterFirst)

        indexer.markIndexStale()
        let afterRestore = await indexer.reconcileAtLaunch(container: container)
        XCTAssertEqual(afterRestore, .rebuild, "A restored store is rebuilt on the next launch check.")
    }

    @MainActor
    func testStartFreshRemovesEverythingIncludingPendingEdits() async throws {
        let container = try makeContainer()
        let client = Client(firstName: "Ava", lastName: "Martinez", phone: "+15552345678")
        container.mainContext.insert(client)

        let index = RecordingSpotlightIndex()
        let indexer = makeIndexer(index, debounce: .milliseconds(150))
        indexer.applyPrivacyPolicy(allowsIndexing: true)
        indexer.scheduleIndex(client: client)
        indexer.removeAllItems()
        try await Task.sleep(for: .milliseconds(400))

        XCTAssertEqual(index.calls, [.deleteAll], "A debounced edit must not re-add a wiped client.")
    }
}
