import SwiftData
import XCTest
@testable import Pawtrackr
#if canImport(SQLite3)
import SQLite3
#endif

@MainActor
final class DataSafetyMonitorTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var tempDirectory: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        suiteName = "DataSafetyMonitorTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let schema = Schema(PawtrackrSchema.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [config])
        context = container.mainContext
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: tempDirectory)
        context = nil
        container = nil
        tempDirectory = nil
        defaults = nil
        suiteName = nil
    }

    func testHealthyClientCountClearsDataLossWarning() throws {
        defaults.set(true, forKey: DataSafetyMonitor.suspectedDataLossKey)
        context.insert(Client(firstName: "Riley", lastName: "Parker"))
        try context.save()

        DataSafetyMonitor.evaluateClientStoreState(in: context, appSupportURL: tempDirectory, userDefaults: defaults)

        XCTAssertFalse(defaults.bool(forKey: DataSafetyMonitor.suspectedDataLossKey))
        XCTAssertEqual(defaults.integer(forKey: DataSafetyMonitor.lastKnownClientCountKey), 1)
    }

    func testDropToZeroAfterKnownClientsFlagsDataLossWarning() {
        defaults.set(4, forKey: DataSafetyMonitor.lastKnownClientCountKey)

        DataSafetyMonitor.evaluateClientStoreState(in: context, appSupportURL: tempDirectory, userDefaults: defaults)

        XCTAssertTrue(defaults.bool(forKey: DataSafetyMonitor.suspectedDataLossKey))
        XCTAssertFalse(
            (defaults.string(forKey: DataSafetyMonitor.suspectedDataLossMessageKey) ?? "").isEmpty
        )
    }

    func testPartialDropIsTreatedAsHealthy() throws {
        // A deleted client or a sync that's still importing lowers the count.
        // Flagging that used to lock Start Fresh behind a banner that never cleared.
        defaults.set(4, forKey: DataSafetyMonitor.lastKnownClientCountKey)
        context.insert(Client(firstName: "New", lastName: "Client"))
        try context.save()
        try makeBackup(named: "PreMigrationBackup-1.0.3-4-2026-10-01T10-00-00Z", clientRows: 4)

        DataSafetyMonitor.evaluateClientStoreState(in: context, appSupportURL: tempDirectory, userDefaults: defaults)

        XCTAssertFalse(defaults.bool(forKey: DataSafetyMonitor.suspectedDataLossKey))
        XCTAssertEqual(defaults.integer(forKey: DataSafetyMonitor.lastKnownClientCountKey), 1)
        XCTAssertNil(defaults.string(forKey: StoreBackupRestore.offerDirectoryKey))
    }

    func testDropToZeroNamesTheBackupThatStillHasClients() throws {
        defaults.set(4, forKey: DataSafetyMonitor.lastKnownClientCountKey)
        try makeBackup(named: "PreMigrationBackup-1.0.3-4-2026-10-01T10-00-00Z", clientRows: 4)

        DataSafetyMonitor.evaluateClientStoreState(in: context, appSupportURL: tempDirectory, userDefaults: defaults)

        XCTAssertTrue(defaults.bool(forKey: DataSafetyMonitor.suspectedDataLossKey))
        XCTAssertEqual(
            defaults.string(forKey: DataSafetyMonitor.suspectedDataLossRecoveryDetailKey),
            "PreMigrationBackup-1.0.3-4-2026-10-01T10-00-00Z"
        )
        XCTAssertEqual(defaults.integer(forKey: StoreBackupRestore.offerClientCountKey), 4)
    }

    func testResetBackupIsOfferedWithoutAnyRecordedClientCount() throws {
        // 1.0.1 and 1.0.2 never wrote lastKnownClientCount, so a user who lost
        // clients to the 1.0.2 recovery screen reads 0 here. The backup alone
        // has to be enough to surface the restore.
        context.insert(Client(firstName: "Nina", lastName: "Afterreset"))
        try context.save()
        try makeBackup(named: "RecoveryBackup-2026-09-26T02-50-49Z", clientRows: 3)

        DataSafetyMonitor.evaluateClientStoreState(in: context, appSupportURL: tempDirectory, userDefaults: defaults)

        XCTAssertEqual(defaults.string(forKey: StoreBackupRestore.offerDirectoryKey), "RecoveryBackup-2026-09-26T02-50-49Z")
        XCTAssertEqual(defaults.integer(forKey: StoreBackupRestore.offerClientCountKey), 3)
        XCTAssertFalse(defaults.bool(forKey: DataSafetyMonitor.suspectedDataLossKey))
    }

    func testResetBackupIsNotOfferedOnceItsClientsAreBack() throws {
        // Users whose sync worked got their clients back from iCloud after the
        // reset; the backup's clients are all in the live store already.
        let returned = Client(firstName: "Ava", lastName: "Martinez")
        context.insert(returned)
        try context.save()
        let directory = tempDirectory.appendingPathComponent("RecoveryBackup-2026-09-26T02-50-49Z", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try makeSQLiteStore(at: directory.appendingPathComponent("Pawtrackr.store"), clientRows: 0)
        try insertClientUUID(returned.uuid, into: directory.appendingPathComponent("Pawtrackr.store"))

        DataSafetyMonitor.evaluateClientStoreState(in: context, appSupportURL: tempDirectory, userDefaults: defaults)

        XCTAssertNil(defaults.string(forKey: StoreBackupRestore.offerDirectoryKey))
    }

    func testABackupHoldingOnlySampleClientsIsNeverNamedAsRecovery() throws {
        // Sample clients (fixed UUIDs) are practice rows. A per-build backup
        // taken while only they were loaded has none of the user's clients.
        defaults.set(4, forKey: DataSafetyMonitor.lastKnownClientCountKey)
        let directory = tempDirectory.appendingPathComponent("PreMigrationBackup-1.0.3-4-2026-10-01T10-00-00Z", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = directory.appendingPathComponent("Pawtrackr.store")
        try makeSQLiteStore(at: store, clientRows: 0)
        try insertClientUUID(SampleData.avaClientID, into: store, primaryKey: 100)
        try insertClientUUID(SampleData.jordanClientID, into: store, primaryKey: 101)

        DataSafetyMonitor.evaluateClientStoreState(in: context, appSupportURL: tempDirectory, userDefaults: defaults)

        XCTAssertTrue(defaults.bool(forKey: DataSafetyMonitor.suspectedDataLossKey))
        XCTAssertNil(defaults.string(forKey: DataSafetyMonitor.suspectedDataLossRecoveryDetailKey),
                     "Only a backup with the user's own clients is offered as the way back.")
        XCTAssertNil(defaults.string(forKey: StoreBackupRestore.offerDirectoryKey))
    }

    private func makeBackup(named name: String, clientRows: Int) throws {
        let directory = tempDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try makeSQLiteStore(at: directory.appendingPathComponent("Pawtrackr.store"), clientRows: clientRows)
    }

    private func insertClientUUID(_ uuid: UUID, into url: URL, primaryKey: Int = 100) throws {
        #if canImport(SQLite3)
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        guard let database else { return XCTFail("Failed to open \(url.lastPathComponent)") }
        defer { sqlite3_close(database) }
        let hex = withUnsafeBytes(of: uuid.uuid) { $0.map { String(format: "%02X", $0) }.joined() }
        XCTAssertEqual(sqlite3_exec(database, "INSERT INTO ZCLIENT (Z_PK, ZUUID) VALUES (\(primaryKey), X'\(hex)')", nil, nil, nil), SQLITE_OK)
        #else
        throw XCTSkip("SQLite3 is unavailable on this platform")
        #endif
    }

    private func makeSQLiteStore(at url: URL, clientRows: Int) throws {
        #if canImport(SQLite3)
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        guard let database else {
            XCTFail("Failed to open SQLite test database")
            return
        }
        defer { sqlite3_close(database) }

        XCTAssertEqual(sqlite3_exec(database, "CREATE TABLE ZCLIENT (Z_PK INTEGER PRIMARY KEY, ZUUID BLOB)", nil, nil, nil), SQLITE_OK)
        for index in 0..<clientRows {
            XCTAssertEqual(sqlite3_exec(database, "INSERT INTO ZCLIENT (Z_PK, ZUUID) VALUES (\(index + 1), randomblob(16))", nil, nil, nil), SQLITE_OK)
        }
        #else
        throw XCTSkip("SQLite3 is unavailable on this platform")
        #endif
    }
}
