import XCTest
#if canImport(SQLite3)
import SQLite3
#endif
@testable import Pawtrackr

final class StoreFileMigrationTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PawtrackrStoreMigrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
    }

    func testMigratesLegacyDefaultStoreWhenNamedStoreIsMissing() throws {
        try "legacy-data".write(to: tempDirectory.appendingPathComponent("default.store"), atomically: true, encoding: .utf8)
        try "legacy-wal".write(to: tempDirectory.appendingPathComponent("default.store-wal"), atomically: true, encoding: .utf8)

        let outcome = StoreFileMigration.migrateLegacyDefaultStoreIfNeeded(appSupportURL: tempDirectory)

        XCTAssertEqual(outcome.action, .migratedToMissingNamedStore)
        XCTAssertEqual(outcome.movedFiles, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDirectory.appendingPathComponent("default.store").path))
        XCTAssertEqual(
            try String(contentsOf: tempDirectory.appendingPathComponent("Pawtrackr.store"), encoding: .utf8),
            "legacy-data"
        )
        XCTAssertEqual(
            try String(contentsOf: tempDirectory.appendingPathComponent("Pawtrackr.store-wal"), encoding: .utf8),
            "legacy-wal"
        )
    }

    func testRestoresLegacyStoreOverEmptyNamedStore() throws {
        try makeSQLiteStore(at: tempDirectory.appendingPathComponent("Pawtrackr.store"), clientRows: 0)
        try makeSQLiteStore(at: tempDirectory.appendingPathComponent("default.store"), clientRows: 3)

        let outcome = StoreFileMigration.migrateLegacyDefaultStoreIfNeeded(appSupportURL: tempDirectory)

        XCTAssertEqual(outcome.action, .restoredLegacyOverEmptyNamedStore)
        XCTAssertEqual(outcome.movedFiles, 1)
        XCTAssertEqual(outcome.backedUpFiles, 1)
        XCTAssertEqual(try clientRowCount(in: tempDirectory.appendingPathComponent("Pawtrackr.store")), 3)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDirectory.appendingPathComponent("default.store").path))
        let backups = try FileManager.default.contentsOfDirectory(at: tempDirectory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("StoreMigrationBackup-") }
        XCTAssertEqual(backups.count, 1)
    }

    func testDoesNotOverwriteNamedStoreWithOperationalRows() throws {
        try makeSQLiteStore(at: tempDirectory.appendingPathComponent("Pawtrackr.store"), clientRows: 1)
        try makeSQLiteStore(at: tempDirectory.appendingPathComponent("default.store"), clientRows: 3)

        let outcome = StoreFileMigration.migrateLegacyDefaultStoreIfNeeded(appSupportURL: tempDirectory)

        XCTAssertEqual(outcome.action, .skippedNamedStoreHasData)
        XCTAssertEqual(try clientRowCount(in: tempDirectory.appendingPathComponent("Pawtrackr.store")), 1)
        XCTAssertEqual(try clientRowCount(in: tempDirectory.appendingPathComponent("default.store")), 3)
    }

    func testPreMigrationBackupCopiesCurrentAndLegacyStoresOncePerBuild() throws {
        let suiteName = "StoreFileMigrationTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        try "current-data".write(to: tempDirectory.appendingPathComponent("Pawtrackr.store"), atomically: true, encoding: .utf8)
        try "legacy-data".write(to: tempDirectory.appendingPathComponent("default.store"), atomically: true, encoding: .utf8)

        let first = StoreFileMigration.backupStoresForCurrentBuildIfNeeded(appSupportURL: tempDirectory, userDefaults: defaults)
        let second = StoreFileMigration.backupStoresForCurrentBuildIfNeeded(appSupportURL: tempDirectory, userDefaults: defaults)

        XCTAssertEqual(first.copiedFiles, 2)
        XCTAssertEqual(second.copiedFiles, 0)

        let backupDirectory = try XCTUnwrap(first.backupDirectory)
        XCTAssertEqual(
            try String(contentsOf: backupDirectory.appendingPathComponent("Pawtrackr.store"), encoding: .utf8),
            "current-data"
        )
        XCTAssertEqual(
            try String(contentsOf: backupDirectory.appendingPathComponent("default.store"), encoding: .utf8),
            "legacy-data"
        )
    }

    private func makeSQLiteStore(at url: URL, clientRows: Int) throws {
        #if canImport(SQLite3)
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
            throw SQLiteTestError.open
        }
        defer { sqlite3_close(database) }

        try execute("CREATE TABLE ZCLIENT (Z_PK INTEGER PRIMARY KEY)", database: database)
        if clientRows > 0 {
            for row in 1...clientRows {
                try execute("INSERT INTO ZCLIENT (Z_PK) VALUES (\(row))", database: database)
            }
        }
        #else
        throw XCTSkip("SQLite3 is not available in this test environment.")
        #endif
    }

    private func clientRowCount(in url: URL) throws -> Int {
        #if canImport(SQLite3)
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
            throw SQLiteTestError.open
        }
        defer { sqlite3_close(database) }

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, "SELECT COUNT(*) FROM ZCLIENT", -1, &statement, nil) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW
        else {
            throw SQLiteTestError.query
        }
        return Int(sqlite3_column_int64(statement, 0))
        #else
        throw XCTSkip("SQLite3 is not available in this test environment.")
        #endif
    }

    #if canImport(SQLite3)
    private func execute(_ sql: String, database: OpaquePointer) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        defer {
            if let errorMessage {
                sqlite3_free(errorMessage)
            }
        }

        guard sqlite3_exec(database, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            throw SQLiteTestError.exec(errorMessage.map { String(cString: $0) } ?? "unknown")
        }
    }
    #endif

    private enum SQLiteTestError: Error {
        case open
        case query
        case exec(String)
    }
}
