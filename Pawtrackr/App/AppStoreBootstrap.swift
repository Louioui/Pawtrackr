//
//  AppStoreBootstrap.swift
//  Pawtrackr
//
//  Opens the one ModelContainer this process uses, after the store-file work
//  that has to come first.
//
//  App Intents and the app share one local container. Scheduled restores,
//  per-build backups and legacy store moves finish before it is opened.
//

import Foundation
import OSLog
import SwiftData

enum AppStoreBootstrap {
    static let lastInitErrorKey = "pawtrackr.lastInitError"
    struct Outcome {
        /// nil when the store couldn't be opened or failed its health check;
        /// the app then shows DataStoreRecoveryView.
        let container: ModelContainer?
        let isInMemory: Bool
        /// A backup from this device replaced the store and opened.
        var restoredLocalBackup = false
    }

    @MainActor private static var cached: Outcome?

    /// Runs the store-file work and opens the store the first time it's
    /// called in this process; every later call gets the same outcome, a
    /// failed one included, so a broken store isn't reopened per intent.
    @MainActor
    static func shared() -> Outcome {
        if let cached { return cached }
        let outcome = openStore()
        cached = outcome
        return outcome
    }

    @MainActor
    private static func openStore() -> Outcome {
        let logger = Logger(subsystem: "com.pawtrackr", category: "PawtrackrApp")
        let inMemory = AppRuntime.prefersInMemoryStore
        let schema = Schema(PawtrackrSchema.models)
        let defaults = UserDefaults.standard

        var didRestoreThisLaunch = false
        var restoreArchiveName: String?
        if !inMemory {
            // A restore the user confirmed last session. It has to swap files
            // before anything opens the store, and before the per-build backup
            // copies whatever is live.
            switch StoreBackupRestore.performScheduledRestoreIfNeeded() {
            case .restored(let directoryName, let clientCount, let archivedDirectoryName):
                logger.notice("Restored \(clientCount) clients from \(directoryName, privacy: .public); previous store archived as \(archivedDirectoryName ?? "none", privacy: .public).")
                didRestoreThisLaunch = true
                restoreArchiveName = archivedDirectoryName
            case .failed(let reason):
                logger.error("Scheduled store restore didn't run: \(reason.rawValue, privacy: .public)")
            case .none:
                break
            }

            let backupOutcome = StoreFileMigration.backupStoresForCurrentBuildIfNeeded()
            if backupOutcome.copiedFiles > 0 {
                logger.info("Pre-migration SwiftData store backup completed: copied=\(backupOutcome.copiedFiles)")
            }
            let migrationOutcome = StoreFileMigration.migrateLegacyDefaultStoreIfNeeded()
            switch migrationOutcome.action {
            case .migratedToMissingNamedStore, .restoredLegacyOverEmptyNamedStore:
                logger.info("Legacy SwiftData store migration completed: moved=\(migrationOutcome.movedFiles), backedUp=\(migrationOutcome.backedUpFiles)")
            case .skippedNamedStoreHasData:
                logger.info("Legacy SwiftData store migration skipped because current store has data.")
            case .skippedUnableToVerifyStoreContents:
                logger.warning("Legacy SwiftData store migration skipped because store contents could not be verified.")
            case .failed(let message):
                logger.error("Legacy SwiftData store migration failed: \(message, privacy: .public)")
            case .none:
                break
            }
        }

        // Keep the existing named store and schema; only local persistence
        // opens it. No migration plan or replacement store is introduced.
        func open() -> ModelContainer? {
            do {
                let configuration = LocalStoreConfiguration.make(schema: schema, isStoredInMemoryOnly: inMemory)
                return try ModelContainer(for: schema, configurations: [configuration])
            } catch {
                logger.critical("Local ModelContainer init failed: \(error.localizedDescription, privacy: .public)")
                defaults.set(error.localizedDescription, forKey: lastInitErrorKey)
                return nil
            }
        }

        var loaded = open()
        var keptRestore = didRestoreThisLaunch
        if loaded == nil, didRestoreThisLaunch {
            // The backup we just swapped in can't be opened. Put back the store
            // that worked before instead of stranding the user on the recovery screen.
            logger.critical("Restored store failed to open; rolling the restore back.")
            StoreBackupRestore.rollBackRestore(archivedDirectoryName: restoreArchiveName)
            keptRestore = false
            loaded = open()
        }
        let restoredLocalBackup = keptRestore && loaded != nil
        guard let container = loaded else {
            return Outcome(container: nil, isInMemory: inMemory)
        }

        guard StoreHealthCheck.isStoreHealthy(container: container) else {
            logger.critical("ModelContainer health check failed.")
            defaults.set("Database integrity check failed.", forKey: lastInitErrorKey)
            return Outcome(container: nil, isInMemory: inMemory)
        }

        defaults.removeObject(forKey: lastInitErrorKey)
        return Outcome(container: container, isInMemory: inMemory, restoredLocalBackup: restoredLocalBackup)
    }
}
