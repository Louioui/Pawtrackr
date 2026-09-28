//
//  AppStoreBootstrap.swift
//  Pawtrackr
//
//  Opens the one ModelContainer this process uses, after the store-file work
//  that has to come first.
//
//  App Intents run inside the app process. When IntentContainerProvider
//  opened its own `.automatic` container, one process had two mirroring
//  delegates on the same store (Apple's field error 134422), and now that
//  upload failures stay on screen until an upload succeeds, a spurious setup
//  failure from that second container would keep the groomer's status red.
//  PawtrackrApp.init and the intents share this instead, so a cold intent
//  launch also runs the scheduled restore, the per-build backup and the
//  legacy move before anything opens the store, and honours the same
//  local-only fallback.
//

import Foundation
import OSLog
import SwiftData

enum AppStoreBootstrap {
    static let lastInitErrorKey = "pawtrackr.lastInitError"
    /// True while launches keep falling back to local-only because CloudKit
    /// mirroring wouldn't start. Read by the support and recovery reports.
    static let cloudKitFallbackActiveKey = "pawtrackr.cloudKitFallbackActive"
    /// When the current run of local-only launches began. Kept across
    /// relaunches so the reports can say how long nothing has uploaded.
    static let cloudKitFallbackSinceKey = "pawtrackr.cloudKitFallbackSince"

    struct Outcome {
        /// nil when the store couldn't be opened or failed its health check;
        /// the app then shows DataStoreRecoveryView.
        let container: ModelContainer?
        let syncMode: CloudKitMonitor.Mode
        let isInMemory: Bool
        /// A backup from this device replaced the store and opened. Its
        /// clients came from the device, not iCloud, so the first-sync
        /// splash mustn't claim they're being restored from iCloud.
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
        let wantsCloudKit = !inMemory && AppRuntime.allowsICloudSync
        let schema = Schema(PawtrackrSchema.models)
        let containerName = inMemory ? "PawtrackrTests" : "Pawtrackr"
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

        #if DEBUG
        // Opt-in (launch argument) and DEBUG-only. It loads a throwaway store
        // and unloads it before SwiftData opens the real one.
        CloudKitSchemaInitializer.runIfRequested()
        #endif

        // Try CloudKit first (the normal path). If that throws, open the same
        // store without mirroring so the groomer lands in a working app rather
        // than on the recovery screen; the monitor then shows the red
        // local-only banner. Every launch tries CloudKit again.
        func open() -> (container: ModelContainer?, fellBackToLocalOnly: Bool, firstError: Error?) {
            do {
                let primaryConfig = ModelConfiguration(
                    containerName,
                    schema: schema,
                    isStoredInMemoryOnly: inMemory,
                    cloudKitDatabase: wantsCloudKit ? .automatic : .none
                )
                return (try ModelContainer(for: schema, configurations: [primaryConfig]), false, nil)
            } catch {
                logger.critical("ModelContainer init failed (cloudkit=\(wantsCloudKit)): \(error.localizedDescription, privacy: .public)")
                guard wantsCloudKit else {
                    defaults.set(error.localizedDescription, forKey: lastInitErrorKey)
                    return (nil, false, error)
                }

                logger.warning("Falling back to local-only ModelContainer so the user can still open the app.")
                do {
                    let fallbackConfig = ModelConfiguration(
                        containerName,
                        schema: schema,
                        isStoredInMemoryOnly: false,
                        cloudKitDatabase: .none
                    )
                    return (try ModelContainer(for: schema, configurations: [fallbackConfig]), true, error)
                } catch let fallbackError {
                    logger.critical("Local-only fallback also failed: \(fallbackError.localizedDescription, privacy: .public)")
                    defaults.set(
                        "CloudKit init failed: \(error.localizedDescription). Local-only fallback also failed: \(fallbackError.localizedDescription)",
                        forKey: lastInitErrorKey
                    )
                    return (nil, false, error)
                }
            }
        }

        var (loaded, fellBackToLocalOnly, firstError) = open()
        var keptRestore = didRestoreThisLaunch
        if loaded == nil, didRestoreThisLaunch {
            // The backup we just swapped in can't be opened. Put back the store
            // that worked before instead of stranding the user on the recovery screen.
            logger.critical("Restored store failed to open; rolling the restore back.")
            StoreBackupRestore.rollBackRestore(archivedDirectoryName: restoreArchiveName)
            keptRestore = false
            (loaded, fellBackToLocalOnly, firstError) = open()
        }
        let restoredLocalBackup = keptRestore && loaded != nil
        if restoredLocalBackup {
            // Only once the restored store is the one staying: after a rollback,
            // the upload record still describes the store that came back. This
            // is UserDefaults work, so it can follow the open; CloudKitMonitor
            // doesn't read the record until PawtrackrApp configures it.
            CloudKitMonitor.resetPersistedSyncStateForLocalStoreReset()
        }

        let intendedMode: CloudKitMonitor.Mode = wantsCloudKit ? .mirroring : .disabled
        guard let container = loaded else {
            return Outcome(container: nil, syncMode: intendedMode, isInMemory: inMemory)
        }

        guard StoreHealthCheck.isStoreHealthy(container: container) else {
            logger.critical("ModelContainer health check failed.")
            defaults.set("Database integrity check failed.", forKey: lastInitErrorKey)
            return Outcome(container: nil, syncMode: intendedMode, isInMemory: inMemory)
        }

        guard wantsCloudKit else {
            return Outcome(container: container, syncMode: .disabled, isInMemory: inMemory, restoredLocalBackup: restoredLocalBackup)
        }

        if fellBackToLocalOnly {
            let since = defaults.object(forKey: cloudKitFallbackSinceKey) as? Date ?? Date()
            let reason = firstError?.localizedDescription ?? "unknown error"
            defaults.set(true, forKey: cloudKitFallbackActiveKey)
            defaults.set(since, forKey: cloudKitFallbackSinceKey)
            defaults.set("CloudKit unavailable: \(reason). Running in local-only mode.", forKey: lastInitErrorKey)
            return Outcome(
                container: container,
                syncMode: .localOnlyFallback(error: reason, since: since),
                isInMemory: inMemory,
                restoredLocalBackup: restoredLocalBackup
            )
        }

        // Mirroring started: this run of local-only launches, if any, is over.
        defaults.removeObject(forKey: cloudKitFallbackActiveKey)
        defaults.removeObject(forKey: cloudKitFallbackSinceKey)
        return Outcome(container: container, syncMode: .mirroring, isInMemory: inMemory, restoredLocalBackup: restoredLocalBackup)
    }
}
