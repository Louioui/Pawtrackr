//
//  StoreFileMigration.swift
//  Pawtrackr
//
//  File-level SwiftData store migrations that must happen before
//  ModelContainer opens the configured store.
//

import Foundation
import OSLog
#if canImport(SQLite3)
import SQLite3
#endif

enum StoreFileMigration {
    enum Action: Equatable {
        case none
        case migratedToMissingNamedStore
        case restoredLegacyOverEmptyNamedStore
        case skippedNamedStoreHasData
        case skippedUnableToVerifyStoreContents
        case failed(String)
    }

    struct Outcome: Equatable {
        let action: Action
        let movedFiles: Int
        let backedUpFiles: Int
    }

    struct BackupOutcome: Equatable {
        let copiedFiles: Int
        let backupDirectory: URL?
    }

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "StoreFileMigration")
    private static let legacyStoreName = "default.store"
    private static let currentStoreName = "Pawtrackr.store"
    private static let preMigrationBackupBuildKey = "pawtrackr.storeBackup.lastBuild"
    private static let operationalTables = [
        "ZCLIENT",
        "ZPET",
        "ZVISIT",
        "ZPAYMENT",
        "ZVISITITEM",
        "ZCHECKOUTTRANSACTION",
        "ZINVENTORYITEM",
        "ZINVENTORYTRANSACTION",
        "ZLOYALTYLEDGERENTRY"
    ]

    @discardableResult
    static func backupStoresForCurrentBuildIfNeeded(
        appSupportURL overrideAppSupportURL: URL? = nil,
        fileManager: FileManager = .default,
        userDefaults: UserDefaults = .standard
    ) -> BackupOutcome {
        let buildIdentifier = appBuildIdentifier
        guard userDefaults.string(forKey: preMigrationBackupBuildKey) != buildIdentifier else {
            return BackupOutcome(copiedFiles: 0, backupDirectory: nil)
        }

        do {
            let appSupportURL = try overrideAppSupportURL ?? fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )

            let storeFiles = try existingStoreFamily(for: currentStoreName, in: appSupportURL, fileManager: fileManager)
                + existingStoreFamily(for: legacyStoreName, in: appSupportURL, fileManager: fileManager)
            guard !storeFiles.isEmpty else {
                userDefaults.set(buildIdentifier, forKey: preMigrationBackupBuildKey)
                return BackupOutcome(copiedFiles: 0, backupDirectory: nil)
            }

            let stamp = ISO8601DateFormatter()
                .string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            let safeBuild = buildIdentifier.replacingOccurrences(of: "/", with: "-")
            let backupDirectory = appSupportURL.appendingPathComponent("PreMigrationBackup-\(safeBuild)-\(stamp)", isDirectory: true)
            try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)

            var copied = 0
            for url in storeFiles {
                try fileManager.copyItem(at: url, to: backupDirectory.appendingPathComponent(url.lastPathComponent))
                copied += 1
            }

            let manifest = [
                "Pawtrackr automatic pre-migration backup",
                "Created: \(Date().formatted(date: .complete, time: .standard))",
                "App build: \(buildIdentifier)",
                "Copied files:",
                storeFiles.map { "- \($0.lastPathComponent)" }.joined(separator: "\n")
            ].joined(separator: "\n")
            try manifest.write(
                to: backupDirectory.appendingPathComponent("README.txt"),
                atomically: true,
                encoding: .utf8
            )

            userDefaults.set(buildIdentifier, forKey: preMigrationBackupBuildKey)
            log.info("Created pre-migration store backup with \(copied, privacy: .public) file(s).")
            return BackupOutcome(copiedFiles: copied, backupDirectory: backupDirectory)
        } catch {
            log.error("Pre-migration store backup failed: \(error.localizedDescription, privacy: .public)")
            return BackupOutcome(copiedFiles: 0, backupDirectory: nil)
        }
    }

    /// Moves data from SwiftData's old unnamed `default.store` into the named
    /// `Pawtrackr.store` before SwiftData can create a fresh empty database.
    ///
    /// Some builds used the default store name, while current builds configure a
    /// named store. Updating the app preserves both files, but SwiftData only
    /// opens the configured name, which makes existing clients appear erased.
    @discardableResult
    static func migrateLegacyDefaultStoreIfNeeded(
        appSupportURL overrideAppSupportURL: URL? = nil,
        fileManager: FileManager = .default
    ) -> Outcome {
        do {
            let appSupportURL = try overrideAppSupportURL ?? fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )

            let legacyFamily = try existingStoreFamily(for: legacyStoreName, in: appSupportURL, fileManager: fileManager)
            guard !legacyFamily.isEmpty else {
                return Outcome(action: .none, movedFiles: 0, backedUpFiles: 0)
            }

            let currentFamily = try existingStoreFamily(for: currentStoreName, in: appSupportURL, fileManager: fileManager)
            if currentFamily.isEmpty {
                let moved = try moveStoreFamily(legacyFamily, from: legacyStoreName, to: currentStoreName, in: appSupportURL, fileManager: fileManager)
                log.info("Migrated legacy default.store to Pawtrackr.store before opening SwiftData.")
                return Outcome(action: .migratedToMissingNamedStore, movedFiles: moved, backedUpFiles: 0)
            }

            let currentStoreURL = appSupportURL.appendingPathComponent(currentStoreName)
            let legacyStoreURL = appSupportURL.appendingPathComponent(legacyStoreName)
            guard let currentHasOperationalRows = hasOperationalRows(in: currentStoreURL),
                  let legacyHasOperationalRows = hasOperationalRows(in: legacyStoreURL)
            else {
                log.warning("Skipped legacy store migration because store contents could not be verified safely.")
                return Outcome(action: .skippedUnableToVerifyStoreContents, movedFiles: 0, backedUpFiles: 0)
            }

            guard !currentHasOperationalRows else {
                log.info("Skipped legacy store migration because Pawtrackr.store already contains operational data.")
                return Outcome(action: .skippedNamedStoreHasData, movedFiles: 0, backedUpFiles: 0)
            }

            guard legacyHasOperationalRows else {
                return Outcome(action: .none, movedFiles: 0, backedUpFiles: 0)
            }

            let backedUp = try archiveStoreFamily(currentFamily, in: appSupportURL, fileManager: fileManager)
            let moved = try moveStoreFamily(legacyFamily, from: legacyStoreName, to: currentStoreName, in: appSupportURL, fileManager: fileManager)
            log.info("Restored legacy default.store over an empty Pawtrackr.store backup.")
            return Outcome(action: .restoredLegacyOverEmptyNamedStore, movedFiles: moved, backedUpFiles: backedUp)
        } catch {
            log.error("Legacy store migration failed: \(error.localizedDescription, privacy: .public)")
            return Outcome(action: .failed(error.localizedDescription), movedFiles: 0, backedUpFiles: 0)
        }
    }

    private static func existingStoreFamily(
        for baseName: String,
        in appSupportURL: URL,
        fileManager: FileManager
    ) throws -> [URL] {
        let contents = try fileManager.contentsOfDirectory(
            at: appSupportURL,
            includingPropertiesForKeys: nil,
            options: []
        )

        return contents
            .filter { isStoreFamilyMember($0.lastPathComponent, baseName: baseName) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func isStoreFamilyMember(_ fileName: String, baseName: String) -> Bool {
        fileName == baseName
            || fileName.hasPrefix(baseName + "-")
            || fileName.hasPrefix(baseName + "_")
            || fileName.hasPrefix("." + baseName + "-")
            || fileName.hasPrefix("." + baseName + "_")
    }

    private static func renamedStoreFamilyMember(_ fileName: String, from oldBaseName: String, to newBaseName: String) -> String {
        if fileName.hasPrefix("." + oldBaseName) {
            return "." + newBaseName + String(fileName.dropFirst(oldBaseName.count + 1))
        }
        if fileName.hasPrefix(oldBaseName) {
            return newBaseName + String(fileName.dropFirst(oldBaseName.count))
        }
        return fileName
    }

    private static func moveStoreFamily(
        _ urls: [URL],
        from oldBaseName: String,
        to newBaseName: String,
        in appSupportURL: URL,
        fileManager: FileManager
    ) throws -> Int {
        var moved = 0
        for url in urls {
            let newName = renamedStoreFamilyMember(url.lastPathComponent, from: oldBaseName, to: newBaseName)
            let destination = appSupportURL.appendingPathComponent(newName)
            try fileManager.moveItem(at: url, to: destination)
            moved += 1
        }
        return moved
    }

    private static func archiveStoreFamily(_ urls: [URL], in appSupportURL: URL, fileManager: FileManager) throws -> Int {
        let stamp = ISO8601DateFormatter()
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backupDirectory = appSupportURL.appendingPathComponent("StoreMigrationBackup-\(stamp)", isDirectory: true)
        try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)

        var backedUp = 0
        for url in urls {
            try fileManager.moveItem(at: url, to: backupDirectory.appendingPathComponent(url.lastPathComponent))
            backedUp += 1
        }

        let manifest = [
            "Pawtrackr automatic store migration backup",
            "Created: \(Date().formatted(date: .complete, time: .standard))",
            "Reason: an empty Pawtrackr.store was replaced with data from legacy default.store.",
            "Backed up files:",
            urls.isEmpty ? "- none" : urls.map { "- \($0.lastPathComponent)" }.joined(separator: "\n")
        ].joined(separator: "\n")
        try manifest.write(
            to: backupDirectory.appendingPathComponent("README.txt"),
            atomically: true,
            encoding: .utf8
        )

        return backedUp
    }

    private static func hasOperationalRows(in storeURL: URL) -> Bool? {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return false }

        #if canImport(SQLite3)
        var database: OpaquePointer?
        guard sqlite3_open_v2(storeURL.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK,
              let database
        else {
            if let database {
                sqlite3_close(database)
            }
            return nil
        }
        defer { sqlite3_close(database) }

        for table in operationalTables where tableExists(table, in: database) {
            guard let rows = rowCount(in: table, database: database) else { return nil }
            if rows > 0 { return true }
        }
        return false
        #else
        return nil
        #endif
    }

    static func clientRowCount(in storeURL: URL) -> Int? {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return 0 }

        #if canImport(SQLite3)
        var database: OpaquePointer?
        guard sqlite3_open_v2(storeURL.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK,
              let database
        else {
            if let database {
                sqlite3_close(database)
            }
            return nil
        }
        defer { sqlite3_close(database) }

        guard tableExists("ZCLIENT", in: database) else { return 0 }
        return rowCount(in: "ZCLIENT", database: database)
        #else
        return nil
        #endif
    }

    private static var appBuildIdentifier: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info?["CFBundleVersion"] as? String ?? "unknown"
        return "\(version)-\(build)"
    }

    #if canImport(SQLite3)
    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private static func tableExists(_ table: String, in database: OpaquePointer) -> Bool {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(
            database,
            "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = ?",
            -1,
            &statement,
            nil
        ) == SQLITE_OK else {
            return false
        }

        sqlite3_bind_text(statement, 1, table, -1, sqliteTransient)
        guard sqlite3_step(statement) == SQLITE_ROW else { return false }
        return sqlite3_column_int64(statement, 0) > 0
    }

    private static func rowCount(in table: String, database: OpaquePointer) -> Int? {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(database, "SELECT COUNT(*) FROM \(table)", -1, &statement, nil) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW
        else {
            return nil
        }

        return Int(sqlite3_column_int64(statement, 0))
    }
    #endif
}
