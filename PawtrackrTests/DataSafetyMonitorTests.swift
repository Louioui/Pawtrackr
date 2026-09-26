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

    func testPartialDropWithRecoveryCandidateFlagsDataLossWarning() throws {
        defaults.set(4, forKey: DataSafetyMonitor.lastKnownClientCountKey)
        context.insert(Client(firstName: "New", lastName: "Client"))
        try context.save()
        try makeSQLiteStore(at: tempDirectory.appendingPathComponent("default.store"), clientRows: 4)

        DataSafetyMonitor.evaluateClientStoreState(in: context, appSupportURL: tempDirectory, userDefaults: defaults)

        XCTAssertTrue(defaults.bool(forKey: DataSafetyMonitor.suspectedDataLossKey))
        XCTAssertTrue((defaults.string(forKey: DataSafetyMonitor.suspectedDataLossMessageKey) ?? "").contains("only 1 client"))
        XCTAssertTrue((defaults.string(forKey: DataSafetyMonitor.suspectedDataLossRecoveryDetailKey) ?? "").contains("4 client row"))
        XCTAssertEqual(defaults.integer(forKey: DataSafetyMonitor.lastKnownClientCountKey), 4)
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

        XCTAssertEqual(sqlite3_exec(database, "CREATE TABLE ZCLIENT (Z_PK INTEGER PRIMARY KEY)", nil, nil, nil), SQLITE_OK)
        for index in 0..<clientRows {
            XCTAssertEqual(sqlite3_exec(database, "INSERT INTO ZCLIENT (Z_PK) VALUES (\(index + 1))", nil, nil, nil), SQLITE_OK)
        }
        #else
        throw XCTSkip("SQLite3 is unavailable on this platform")
        #endif
    }
}
