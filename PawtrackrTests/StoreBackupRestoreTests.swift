import XCTest
import SwiftData
#if canImport(SQLite3)
import SQLite3
#endif
@testable import Pawtrackr

final class StoreBackupRestoreTests: XCTestCase {
    private var appSupport: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private let fileManager = FileManager.default

    override func setUpWithError() throws {
        appSupport = fileManager.temporaryDirectory
            .appendingPathComponent("StoreBackupRestoreTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: appSupport, withIntermediateDirectories: true)
        suiteName = "StoreBackupRestoreTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? fileManager.removeItem(at: appSupport)
        appSupport = nil
        defaults = nil
        suiteName = nil
    }

    // MARK: - Discovery

    func testCandidatesReportKindAndClientCountAndSkipUnrelatedFolders() throws {
        try copyFixture(into: "RecoveryBackup-2026-09-26T02-50-49Z")
        try makeSQLiteStore(in: "PreMigrationBackup-1.0.3-4-2026-10-01T10-00-00Z", clientRows: 5)
        try makeSQLiteStore(in: "PreRestoreBackup-2026-10-02T10-00-00Z", clientRows: 1)
        try makeSQLiteStore(in: "SomethingElse", clientRows: 9)
        try fileManager.createDirectory(at: appSupport.appendingPathComponent("RecoveryBackup-no-store"), withIntermediateDirectories: true)

        let candidates = StoreBackupRestore.candidates(appSupportURL: appSupport)
        let byName = Dictionary(uniqueKeysWithValues: candidates.map { ($0.directoryName, $0) })

        XCTAssertEqual(candidates.count, 3)
        XCTAssertEqual(byName["RecoveryBackup-2026-09-26T02-50-49Z"]?.kind, .recoveryReset)
        XCTAssertEqual(byName["RecoveryBackup-2026-09-26T02-50-49Z"]?.clientCount, 3)
        XCTAssertEqual(byName["PreMigrationBackup-1.0.3-4-2026-10-01T10-00-00Z"]?.kind, .preUpdate)
        XCTAssertEqual(byName["PreMigrationBackup-1.0.3-4-2026-10-01T10-00-00Z"]?.clientCount, 5)
        XCTAssertEqual(byName["PreRestoreBackup-2026-10-02T10-00-00Z"]?.kind, .preRestore)
        // Dated from the folder name, not the (just-now) filesystem creation date.
        XCTAssertEqual(
            byName["RecoveryBackup-2026-09-26T02-50-49Z"]?.createdAt,
            ISO8601DateFormatter().date(from: "2026-09-26T02:50:49Z")
        )
        XCTAssertEqual(candidates.first?.directoryName, "PreRestoreBackup-2026-10-02T10-00-00Z", "Newest first")
    }

    // MARK: - Offer policy

    func testResetBackupIsOfferedEvenWhenTheUserReOnboarded() {
        // The 1.0.2 incident: the reset backup holds the real clients, the live
        // store holds sample data plus whatever was re-entered since.
        let reset = candidate(.recoveryReset, uuids: [a, b, c])
        let offer = StoreBackupRestore.offer(from: [reset], liveClientUUIDs: [d, e], dismissed: [], currentBuild: "1.0.3-4")
        XCTAssertEqual(offer, StoreBackupRestore.Offer(candidate: reset, missingClientCount: 3))
    }

    func testOfferCountsOnlyClientsMissingFromTheLiveStore() {
        let reset = candidate(.recoveryReset, uuids: [a, b, c])
        XCTAssertEqual(
            StoreBackupRestore.offer(from: [reset], liveClientUUIDs: [a, b], dismissed: [], currentBuild: "1.0.3-4")?.missingClientCount,
            1
        )
        XCTAssertNil(
            StoreBackupRestore.offer(from: [reset], liveClientUUIDs: [a, b, c, d], dismissed: [], currentBuild: "1.0.3-4"),
            "iCloud already brought every client back; nothing to offer."
        )
    }

    func testResetBackupMadeByTheCurrentBuildIsNotOffered() {
        // The recovery screen only appears when this build couldn't open the
        // store, so offering that store back would loop.
        let sameBuild = candidate(.recoveryReset, uuids: [a], name: "RecoveryBackup-1.0.3-4-2026-10-01T10-00-00Z")
        let olderBuild = candidate(.recoveryReset, uuids: [b], name: "RecoveryBackup-1.0.2-3-2026-09-26T02-50-49Z")
        XCTAssertEqual(sameBuild.build, "1.0.3-4")
        XCTAssertNil(candidate(.recoveryReset, uuids: [a], name: "RecoveryBackup-2026-09-26T02-50-49Z").build)

        XCTAssertNil(StoreBackupRestore.offer(from: [sameBuild], liveClientUUIDs: [], dismissed: [], currentBuild: "1.0.3-4"))
        XCTAssertEqual(
            StoreBackupRestore.offer(from: [sameBuild, olderBuild], liveClientUUIDs: [], dismissed: [], currentBuild: "1.0.3-4")?.candidate,
            olderBuild
        )
    }

    func testPreUpdateCopiesAreOfferedOnlyWhenTheLiveStoreIsEmpty() {
        let preUpdate = candidate(.preUpdate, uuids: [a, b, c, d, e])
        XCTAssertNil(StoreBackupRestore.offer(from: [preUpdate], liveClientUUIDs: [a, b, c, d], dismissed: [], currentBuild: "x"),
                     "Deleting a client must not make the previous build's copy look like lost data.")
        XCTAssertEqual(StoreBackupRestore.offer(from: [preUpdate], liveClientUUIDs: [], dismissed: [], currentBuild: "x")?.missingClientCount, 5)
    }

    func testDismissedEmptyAndPreRestoreBackupsAreNeverOffered() {
        let dismissed = candidate(.recoveryReset, uuids: [a, b], name: "RecoveryBackup-dismissed")
        let empty = candidate(.recoveryReset, uuids: [])
        let preRestore = candidate(.preRestore, uuids: [c, d, e])

        XCTAssertNil(StoreBackupRestore.offer(
            from: [dismissed, empty, preRestore],
            liveClientUUIDs: [],
            dismissed: ["RecoveryBackup-dismissed"],
            currentBuild: "x"
        ))
    }

    func testOfferPrefersTheBackupMissingTheMostClients() {
        let small = candidate(.recoveryReset, uuids: [a], name: "RecoveryBackup-small")
        let large = candidate(.recoveryReset, uuids: [b, c, d], name: "RecoveryBackup-large")
        XCTAssertEqual(StoreBackupRestore.offer(from: [small, large], liveClientUUIDs: [], dismissed: [], currentBuild: "x")?.candidate, large)
    }

    func testPublishAndDismissOffer() throws {
        try copyFixture(into: "RecoveryBackup-2026-09-26T02-50-49Z")

        StoreBackupRestore.publishOffer(liveClientUUIDs: [], appSupportURL: appSupport, userDefaults: defaults)
        XCTAssertEqual(defaults.string(forKey: StoreBackupRestore.offerDirectoryKey), "RecoveryBackup-2026-09-26T02-50-49Z")
        XCTAssertEqual(defaults.integer(forKey: StoreBackupRestore.offerClientCountKey), 3)

        StoreBackupRestore.dismissOffer(directoryName: "RecoveryBackup-2026-09-26T02-50-49Z", userDefaults: defaults)
        XCTAssertNil(defaults.string(forKey: StoreBackupRestore.offerDirectoryKey))

        StoreBackupRestore.publishOffer(liveClientUUIDs: [], appSupportURL: appSupport, userDefaults: defaults)
        XCTAssertNil(defaults.string(forKey: StoreBackupRestore.offerDirectoryKey), "A dismissed backup stays dismissed.")
    }

    func testDismissAllCurrentBackupsSilencesEveryOffer() throws {
        // Start Fresh: every existing backup holds data the user chose to erase.
        try copyFixture(into: "RecoveryBackup-2026-09-26T02-50-49Z")
        try makeSQLiteStore(in: "PreMigrationBackup-1.0.3-4-2026-10-01T10-00-00Z", clientRows: 5)

        StoreBackupRestore.dismissAllCurrentBackups(appSupportURL: appSupport, userDefaults: defaults)
        StoreBackupRestore.publishOffer(liveClientUUIDs: [], appSupportURL: appSupport, userDefaults: defaults)

        XCTAssertNil(defaults.string(forKey: StoreBackupRestore.offerDirectoryKey))
    }

    func testCandidatesReadClientUUIDsFromTheStore() throws {
        try copyFixture(into: "RecoveryBackup-2026-09-26T02-50-49Z")
        let backup = try XCTUnwrap(StoreBackupRestore.candidates(appSupportURL: appSupport).first)
        XCTAssertEqual(backup.clientUUIDs.count, 3)
        XCTAssertTrue(backup.clientUUIDs.contains(UUID(uuidString: "46330C38-F3AF-4AEA-AF89-D066DB9D0B12")!), "Ava Martinez")
    }

    // MARK: - Restore

    func testScheduledRestoreSwapsInTheBackupAndArchivesTheLiveStore() throws {
        // Live store written by the current app: one client entered after the reset.
        let liveStore = appSupport.appendingPathComponent("Pawtrackr.store")
        do {
            let context = ModelContext(try makeContainer(at: liveStore))
            context.insert(Client(firstName: "Nina", lastName: "Afterreset"))
            try context.save()
        }
        let backupName = "RecoveryBackup-2026-09-26T02-50-49Z"
        try copyFixture(into: backupName)

        let backup = try XCTUnwrap(StoreBackupRestore.candidates(appSupportURL: appSupport).first { $0.directoryName == backupName })
        StoreBackupRestore.scheduleRestore(of: backup, userDefaults: defaults)

        let outcome = StoreBackupRestore.performScheduledRestoreIfNeeded(appSupportURL: appSupport, userDefaults: defaults)

        guard case .restored(let restoredName, let clientCount, let archiveName?) = outcome else {
            return XCTFail("Expected a restore with an archive, got \(outcome)")
        }
        XCTAssertEqual(restoredName, backupName)
        XCTAssertEqual(clientCount, 3)

        // The restored 1.0.1-era store opens with today's schema.
        let names = try ModelContext(try makeContainer(at: liveStore))
            .fetch(FetchDescriptor<Client>())
            .map { "\($0.firstName) \($0.lastName)" }
        XCTAssertEqual(Set(names), ["Ava Martinez", "Jordan Lee", "Rosa Upgradetest"])

        // Nothing was deleted: the previous live store and the backup both remain.
        let archivedStore = appSupport.appendingPathComponent(archiveName).appendingPathComponent("Pawtrackr.store")
        XCTAssertEqual(StoreFileMigration.clientRowCount(in: archivedStore), 1)
        XCTAssertTrue(fileManager.fileExists(atPath: appSupport.appendingPathComponent(backupName).appendingPathComponent("Pawtrackr.store").path))

        XCTAssertNil(StoreBackupRestore.scheduledRestoreDirectory(userDefaults: defaults))
        XCTAssertTrue(StoreBackupRestore.dismissedDirectories(userDefaults: defaults).contains(backupName))
        XCTAssertEqual(defaults.integer(forKey: StoreBackupRestore.lastRestoredClientCountKey), 3)
    }

    func testRestoreRunsOnlyOnce() throws {
        let backupName = "RecoveryBackup-once"
        try copyFixture(into: backupName)
        schedule(backupName)

        XCTAssertNotEqual(StoreBackupRestore.performScheduledRestoreIfNeeded(appSupportURL: appSupport, userDefaults: defaults), .none)
        XCTAssertEqual(StoreBackupRestore.performScheduledRestoreIfNeeded(appSupportURL: appSupport, userDefaults: defaults), .none)
    }

    func testRestoreRefusesUnsafeOrUnknownFolderNamesAndLeavesLiveStoreAlone() throws {
        try makeSQLiteStore(atPath: "Pawtrackr.store", clientRows: 2)
        try makeSQLiteStore(in: "SomethingElse", clientRows: 9)

        for name in ["../RecoveryBackup-escape", "SomethingElse", ""] {
            schedule(name)
            guard case .failed = StoreBackupRestore.performScheduledRestoreIfNeeded(appSupportURL: appSupport, userDefaults: defaults) else {
                return XCTFail("Expected \(name) to be refused")
            }
        }
        XCTAssertEqual(StoreFileMigration.clientRowCount(in: appSupport.appendingPathComponent("Pawtrackr.store")), 2)
        XCTAssertNotNil(defaults.string(forKey: StoreBackupRestore.lastRestoreFailureKey))
    }

    func testRestoreOfAnEmptyBackupFailsBeforeMovingAnything() throws {
        try makeSQLiteStore(atPath: "Pawtrackr.store", clientRows: 2)
        try makeSQLiteStore(in: "RecoveryBackup-empty", clientRows: 0)
        schedule("RecoveryBackup-empty")

        guard case .failed = StoreBackupRestore.performScheduledRestoreIfNeeded(appSupportURL: appSupport, userDefaults: defaults) else {
            return XCTFail("An empty backup must not replace the live store")
        }
        XCTAssertEqual(StoreFileMigration.clientRowCount(in: appSupport.appendingPathComponent("Pawtrackr.store")), 2)
        let archives = try fileManager.contentsOfDirectory(atPath: appSupport.path).filter { $0.hasPrefix("PreRestoreBackup-") }
        XCTAssertTrue(archives.isEmpty)
    }

    func testRestoreBringsBackMissingPhotosWithoutOverwritingExistingOnes() throws {
        let backupName = "PreMigrationBackup-1.0.3-4-2026-10-01T10-00-00Z"
        try copyFixture(into: backupName)
        let backupBlobs = appSupport.appendingPathComponent(backupName).appendingPathComponent(".Pawtrackr_SUPPORT/_EXTERNAL_DATA")
        try fileManager.createDirectory(at: backupBlobs, withIntermediateDirectories: true)
        try Data("backup-photo".utf8).write(to: backupBlobs.appendingPathComponent("ONLY-IN-BACKUP"))
        try Data("backup-version".utf8).write(to: backupBlobs.appendingPathComponent("IN-BOTH"))

        let liveBlobs = appSupport.appendingPathComponent(".Pawtrackr_SUPPORT/_EXTERNAL_DATA")
        try fileManager.createDirectory(at: liveBlobs, withIntermediateDirectories: true)
        try Data("live-version".utf8).write(to: liveBlobs.appendingPathComponent("IN-BOTH"))

        schedule(backupName)
        guard case .restored = StoreBackupRestore.performScheduledRestoreIfNeeded(appSupportURL: appSupport, userDefaults: defaults) else {
            return XCTFail("Expected restore to succeed")
        }

        XCTAssertEqual(try String(contentsOf: liveBlobs.appendingPathComponent("ONLY-IN-BACKUP"), encoding: .utf8), "backup-photo")
        XCTAssertEqual(try String(contentsOf: liveBlobs.appendingPathComponent("IN-BOTH"), encoding: .utf8), "live-version")
    }

    func testRestoreScheduledTooLongAgoDoesNothing() throws {
        try makeSQLiteStore(atPath: "Pawtrackr.store", clientRows: 2)
        try copyFixture(into: "RecoveryBackup-stale")
        schedule("RecoveryBackup-stale", at: Date(timeIntervalSinceNow: -StoreBackupRestore.scheduleExpiry - 60))

        XCTAssertEqual(
            StoreBackupRestore.performScheduledRestoreIfNeeded(appSupportURL: appSupport, userDefaults: defaults),
            .failed(.expired)
        )
        XCTAssertEqual(StoreFileMigration.clientRowCount(in: appSupport.appendingPathComponent("Pawtrackr.store")), 2)
        XCTAssertEqual(defaults.string(forKey: StoreBackupRestore.lastRestoreFailureKey), "expired")
        XCTAssertNil(StoreBackupRestore.scheduledRestoreDirectory(userDefaults: defaults))
    }

    func testRollBackPutsThePreviousStoreBack() throws {
        try makeSQLiteStore(atPath: "Pawtrackr.store", clientRows: 2)
        try copyFixture(into: "RecoveryBackup-unopenable")
        schedule("RecoveryBackup-unopenable")
        guard case .restored(_, _, let archiveName?) = StoreBackupRestore.performScheduledRestoreIfNeeded(appSupportURL: appSupport, userDefaults: defaults) else {
            return XCTFail("Expected the swap to happen")
        }

        // PawtrackrApp does this when the swapped-in store then fails to open.
        XCTAssertTrue(StoreBackupRestore.rollBackRestore(archivedDirectoryName: archiveName, appSupportURL: appSupport, userDefaults: defaults))

        XCTAssertEqual(StoreFileMigration.clientRowCount(in: appSupport.appendingPathComponent("Pawtrackr.store")), 2)
        XCTAssertFalse(fileManager.fileExists(atPath: appSupport.appendingPathComponent(archiveName).path))
        XCTAssertTrue(fileManager.fileExists(atPath: appSupport.appendingPathComponent("RecoveryBackup-unopenable/Pawtrackr.store").path),
                      "The backup itself is untouched.")
        XCTAssertEqual(defaults.string(forKey: StoreBackupRestore.lastRestoreFailureKey), "unopenable")
        XCTAssertNil(defaults.object(forKey: StoreBackupRestore.lastRestoredClientCountKey))
    }

    // MARK: - Helpers

    private let a = UUID(), b = UUID(), c = UUID(), d = UUID(), e = UUID()

    private func candidate(_ kind: StoreBackupRestore.Kind, uuids: Set<UUID>, name: String? = nil) -> StoreBackupRestore.Candidate {
        StoreBackupRestore.Candidate(
            directoryName: name ?? kind.directoryPrefix + "\(uuids.count)",
            kind: kind,
            createdAt: Date(timeIntervalSince1970: 1_790_000_000),
            clientCount: uuids.count,
            clientUUIDs: uuids
        )
    }

    private func schedule(_ directoryName: String, at date: Date = Date()) {
        defaults.set(directoryName, forKey: StoreBackupRestore.scheduledRestoreKey)
        defaults.set(date, forKey: StoreBackupRestore.scheduledAtKey)
    }

    private func makeContainer(at storeURL: URL) throws -> ModelContainer {
        let schema = Schema(PawtrackrSchema.models)
        let configuration = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func copyFixture(into directoryName: String) throws {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Pawtrackr-1.0.1-build2", withExtension: "sqlite"))
        let directory = appSupport.appendingPathComponent(directoryName, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try fileManager.copyItem(at: fixture, to: directory.appendingPathComponent("Pawtrackr.store"))
    }

    private func makeSQLiteStore(in directoryName: String, clientRows: Int) throws {
        try fileManager.createDirectory(at: appSupport.appendingPathComponent(directoryName), withIntermediateDirectories: true)
        try makeSQLiteStore(atPath: directoryName + "/Pawtrackr.store", clientRows: clientRows)
    }

    /// A minimal stand-in store: just the ZCLIENT columns the counters read.
    private func makeSQLiteStore(atPath relativePath: String, clientRows: Int) throws {
        #if canImport(SQLite3)
        var database: OpaquePointer?
        let path = appSupport.appendingPathComponent(relativePath).path
        guard sqlite3_open(path, &database) == SQLITE_OK, let database else {
            return XCTFail("Couldn't create \(relativePath)")
        }
        defer { sqlite3_close(database) }
        XCTAssertEqual(sqlite3_exec(database, "CREATE TABLE ZCLIENT (Z_PK INTEGER PRIMARY KEY, ZUUID BLOB)", nil, nil, nil), SQLITE_OK)
        for row in 0..<clientRows {
            XCTAssertEqual(sqlite3_exec(database, "INSERT INTO ZCLIENT (Z_PK, ZUUID) VALUES (\(row + 1), randomblob(16))", nil, nil, nil), SQLITE_OK)
        }
        #else
        throw XCTSkip("SQLite3 is unavailable on this platform")
        #endif
    }
}
