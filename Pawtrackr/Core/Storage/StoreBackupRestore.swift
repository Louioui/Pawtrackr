//
//  StoreBackupRestore.swift
//  Pawtrackr
//
//  Finds on-device copies of the SwiftData store and swaps one back in on the
//  next launch, before ModelContainer opens anything.
//
//  Why this exists: 1.0.2 could not open 1.0.1 stores, and the recovery screen
//  steered users into "Reset Local Data", which moved their store into
//  Application Support/RecoveryBackup-<stamp>/ and started an empty one. Those
//  clients are still on the device; this is how they get them back.
//
//  A restore never deletes anything. The live store is moved into
//  PreRestoreBackup-<stamp>/ and the backup is copied (not moved), so every
//  step can be undone by restoring the other folder.
//

import Foundation
import OSLog

enum StoreBackupRestore {
    enum Kind: String, CaseIterable, Sendable {
        /// Moved aside by the recovery screen's "Reset Local Data".
        case recoveryReset
        /// Copied on the first launch of each new build.
        case preUpdate
        /// The empty named store archived by the legacy default.store move.
        case legacyMove
        /// The store that was live when a restore swapped it out.
        case preRestore

        var directoryPrefix: String {
            switch self {
            case .recoveryReset: "RecoveryBackup-"
            case .preUpdate: "PreMigrationBackup-"
            case .legacyMove: "StoreMigrationBackup-"
            case .preRestore: "PreRestoreBackup-"
            }
        }

        init?(directoryName: String) {
            guard let kind = Kind.allCases.first(where: { directoryName.hasPrefix($0.directoryPrefix) }) else {
                return nil
            }
            self = kind
        }
    }

    struct Candidate: Equatable, Identifiable, Sendable {
        /// Folder name inside Application Support. Stored instead of an absolute
        /// path because iOS moves the app container between launches and updates.
        let directoryName: String
        let kind: Kind
        let createdAt: Date
        let clientCount: Int
        /// Empty when the store's client UUIDs couldn't be read.
        let clientUUIDs: Set<UUID>

        var id: String { directoryName }

        init(directoryName: String, kind: Kind, createdAt: Date, clientCount: Int, clientUUIDs: Set<UUID> = []) {
            self.directoryName = directoryName
            self.kind = kind
            self.createdAt = createdAt
            self.clientCount = clientCount
            self.clientUUIDs = clientUUIDs
        }

        /// The app build that wrote the folder ("1.0.3-4"), when its name records
        /// one: "<prefix><build>-<UTC stamp>". 1.0.2's reset backups don't.
        var build: String? {
            let stampLength = "2026-09-26T02-50-49Z".count
            let body = directoryName.dropFirst(kind.directoryPrefix.count)
            guard body.count > stampLength + 1 else { return nil }
            let build = body.dropLast(stampLength + 1)
            return build.isEmpty ? nil : String(build)
        }

        /// Clients in this backup that the live store doesn't have.
        func missingClientCount(liveClientUUIDs: Set<UUID>) -> Int {
            guard !clientUUIDs.isEmpty else {
                // UUIDs unreadable: only an empty live store proves they're missing.
                return liveClientUUIDs.isEmpty ? clientCount : 0
            }
            return clientUUIDs.subtracting(liveClientUUIDs).count
        }
    }

    struct Offer: Equatable, Sendable {
        let candidate: Candidate
        let missingClientCount: Int
    }

    enum Outcome: Equatable {
        case none
        case restored(directoryName: String, clientCount: Int, archivedDirectoryName: String?)
        case failed(FailureReason)
    }

    /// Stored under `lastRestoreFailureKey` so RootView can explain it in the
    /// user's language; details go to the log.
    enum FailureReason: String, Equatable {
        /// Scheduled too long ago; the user has likely kept working since.
        case expired
        /// The backup was invalid or the file swap failed. Nothing changed.
        case failed
        /// The restored store couldn't be opened, so the swap was undone.
        case unopenable
    }

    enum RestoreError: LocalizedError, Equatable {
        case invalidBackupName(String)
        case missingBackupStore(String)
        case emptyBackup(String)

        var errorDescription: String? {
            switch self {
            case .invalidBackupName(let name): "Not a Pawtrackr backup folder: \(name)"
            case .missingBackupStore(let name): "No store file in \(name)"
            case .emptyBackup(let name): "\(name) has no clients to restore"
            }
        }
    }

    static let scheduledRestoreKey = "pawtrackr.restore.scheduledDirectory"
    static let scheduledAtKey = "pawtrackr.restore.scheduledAt"
    static let dismissedDirectoriesKey = "pawtrackr.restore.dismissedDirectories"
    static let lastRestoredClientCountKey = "pawtrackr.restore.lastRestoredClientCount"
    static let lastRestoreFailureKey = "pawtrackr.restore.lastFailure"
    /// Published by `publishOffer` for RootView's banner.
    static let offerDirectoryKey = "pawtrackr.restore.offerDirectory"
    static let offerClientCountKey = "pawtrackr.restore.offerClientCount"

    /// A restore is meant to finish on the relaunch right after it's confirmed.
    /// Past this window the user has probably kept working, and swapping the
    /// store would set that work aside without warning.
    static let scheduleExpiry: TimeInterval = 2 * 60 * 60

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "StoreBackupRestore")
    private static let liveStoreName = "Pawtrackr.store"
    private static let backupStoreNames = ["Pawtrackr.store", "default.store"]

    // MARK: - Discovery

    /// Every backup folder that holds a readable store, newest first.
    static func candidates(
        appSupportURL overrideAppSupportURL: URL? = nil,
        fileManager: FileManager = .default
    ) -> [Candidate] {
        guard let appSupportURL = overrideAppSupportURL ?? defaultAppSupportURL(fileManager: fileManager),
              let entries = try? fileManager.contentsOfDirectory(
                at: appSupportURL,
                includingPropertiesForKeys: [.isDirectoryKey, .creationDateKey, .contentModificationDateKey],
                options: []
              )
        else {
            return []
        }

        return entries
            .compactMap { url -> Candidate? in
                let name = url.lastPathComponent
                guard let kind = Kind(directoryName: name),
                      let storeURL = backupStoreURL(in: url, fileManager: fileManager),
                      let clientCount = StoreFileMigration.clientRowCount(in: storeURL)
                else {
                    return nil
                }
                let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
                let createdAt = timestamp(fromDirectoryName: name)
                    ?? values?.creationDate
                    ?? values?.contentModificationDate
                    ?? .distantPast
                return Candidate(
                    directoryName: name,
                    kind: kind,
                    createdAt: createdAt,
                    clientCount: clientCount,
                    clientUUIDs: StoreFileMigration.clientUUIDs(in: storeURL) ?? []
                )
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// The backup, if any, worth offering proactively. Everything else stays
    /// reachable from Settings › Data Export.
    ///
    /// Offers are about clients the user no longer has, so a backup only counts
    /// for the clients the live store is missing — if iCloud already brought
    /// them back, there's nothing to offer.
    /// - A reset backup is offered whenever it has missing clients: the reset
    ///   is how 1.0.2 users lost theirs, and they often re-onboarded since.
    ///   Not when the current build made it, though: the recovery screen only
    ///   appears when this build couldn't open the store, so offering it back
    ///   would loop.
    /// - Per-build copies exist for every healthy user, so they only count when
    ///   the live store opened with no clients at all.
    static func offer(
        from candidates: [Candidate],
        liveClientUUIDs: Set<UUID>,
        dismissed: Set<String>,
        currentBuild: String = StoreFileMigration.appBuildIdentifier
    ) -> Offer? {
        candidates
            .filter { $0.clientCount > 0 && !dismissed.contains($0.directoryName) }
            .filter { candidate in
                switch candidate.kind {
                case .recoveryReset:
                    return candidate.build != currentBuild
                case .preUpdate, .legacyMove:
                    return liveClientUUIDs.isEmpty
                case .preRestore:
                    return false
                }
            }
            .map { Offer(candidate: $0, missingClientCount: $0.missingClientCount(liveClientUUIDs: liveClientUUIDs)) }
            .filter { $0.missingClientCount > 0 }
            .max { lhs, rhs in
                (lhs.missingClientCount, lhs.candidate.createdAt) < (rhs.missingClientCount, rhs.candidate.createdAt)
            }
    }

    /// Scans for backups and publishes the one to offer (or clears the offer).
    /// Call off the main thread once the live store has opened.
    static func publishOffer(
        liveClientUUIDs: Set<UUID>,
        appSupportURL: URL? = nil,
        userDefaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        let offer = offer(
            from: candidates(appSupportURL: appSupportURL, fileManager: fileManager),
            liveClientUUIDs: liveClientUUIDs,
            dismissed: dismissedDirectories(userDefaults: userDefaults)
        )
        if let offer {
            userDefaults.set(offer.candidate.directoryName, forKey: offerDirectoryKey)
            userDefaults.set(offer.missingClientCount, forKey: offerClientCountKey)
        } else {
            userDefaults.removeObject(forKey: offerDirectoryKey)
            userDefaults.removeObject(forKey: offerClientCountKey)
        }
    }

    static func dismissOffer(directoryName: String, userDefaults: UserDefaults = .standard) {
        var dismissed = dismissedDirectories(userDefaults: userDefaults)
        dismissed.insert(directoryName)
        userDefaults.set(Array(dismissed).sorted(), forKey: dismissedDirectoriesKey)
        if userDefaults.string(forKey: offerDirectoryKey) == directoryName {
            userDefaults.removeObject(forKey: offerDirectoryKey)
            userDefaults.removeObject(forKey: offerClientCountKey)
        }
    }

    /// After an intentional wipe (Start Fresh), every existing backup holds the
    /// data the user just chose to erase; none of them should come back as a
    /// "clients from before the update" offer. They stay listed in Settings.
    static func dismissAllCurrentBackups(
        appSupportURL: URL? = nil,
        userDefaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        for candidate in candidates(appSupportURL: appSupportURL, fileManager: fileManager) {
            dismissOffer(directoryName: candidate.directoryName, userDefaults: userDefaults)
        }
        userDefaults.removeObject(forKey: offerDirectoryKey)
        userDefaults.removeObject(forKey: offerClientCountKey)
    }

    static func dismissedDirectories(userDefaults: UserDefaults = .standard) -> Set<String> {
        Set(userDefaults.stringArray(forKey: dismissedDirectoriesKey) ?? [])
    }

    // MARK: - Scheduling

    /// The swap can't happen while the ModelContainer has the store open, so it
    /// is recorded here and performed by the next launch.
    static func scheduleRestore(of candidate: Candidate, userDefaults: UserDefaults = .standard, now: Date = Date()) {
        userDefaults.set(candidate.directoryName, forKey: scheduledRestoreKey)
        userDefaults.set(now, forKey: scheduledAtKey)
        log.info("Scheduled restore of \(candidate.directoryName, privacy: .public) (\(candidate.clientCount) clients).")
    }

    static func cancelScheduledRestore(userDefaults: UserDefaults = .standard) {
        userDefaults.removeObject(forKey: scheduledRestoreKey)
        userDefaults.removeObject(forKey: scheduledAtKey)
    }

    static func scheduledRestoreDirectory(userDefaults: UserDefaults = .standard) -> String? {
        userDefaults.string(forKey: scheduledRestoreKey)
    }

    // MARK: - Restore (launch-time, before the container opens)

    @discardableResult
    static func performScheduledRestoreIfNeeded(
        appSupportURL overrideAppSupportURL: URL? = nil,
        fileManager: FileManager = .default,
        userDefaults: UserDefaults = .standard,
        now: Date = Date()
    ) -> Outcome {
        guard let directoryName = userDefaults.string(forKey: scheduledRestoreKey) else { return .none }
        let scheduledAt = userDefaults.object(forKey: scheduledAtKey) as? Date
        // Clear first so a restore that crashes halfway can't re-run on every launch.
        cancelScheduledRestore(userDefaults: userDefaults)

        guard let scheduledAt, now.timeIntervalSince(scheduledAt) <= scheduleExpiry else {
            log.notice("Skipped restore of \(directoryName, privacy: .public): scheduled too long ago.")
            return recordFailure(.expired, userDefaults: userDefaults)
        }

        do {
            guard let appSupportURL = overrideAppSupportURL ?? defaultAppSupportURL(fileManager: fileManager) else {
                throw CocoaError(.fileNoSuchFile)
            }
            let outcome = try restore(directoryName: directoryName, appSupportURL: appSupportURL, fileManager: fileManager)
            if case .restored(_, let clientCount, _) = outcome {
                dismissOffer(directoryName: directoryName, userDefaults: userDefaults)
                userDefaults.set(clientCount, forKey: lastRestoredClientCountKey)
                userDefaults.removeObject(forKey: lastRestoreFailureKey)
            }
            return outcome
        } catch {
            log.error("Restore of \(directoryName, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return recordFailure(.failed, userDefaults: userDefaults)
        }
    }

    /// Undoes a restore whose store then failed to open: puts the archived
    /// store back so the user returns to what worked before. The restored files
    /// were copies, so removing them loses nothing — the backup still has them.
    @discardableResult
    static func rollBackRestore(
        archivedDirectoryName: String?,
        appSupportURL overrideAppSupportURL: URL? = nil,
        fileManager: FileManager = .default,
        userDefaults: UserDefaults = .standard
    ) -> Bool {
        guard let appSupportURL = overrideAppSupportURL ?? defaultAppSupportURL(fileManager: fileManager) else { return false }
        for url in storeFamily(named: liveStoreName, in: appSupportURL, fileManager: fileManager) {
            try? fileManager.removeItem(at: url)
        }
        var restoredAll = true
        if let archivedDirectoryName, isSafeDirectoryName(archivedDirectoryName) {
            let archiveURL = appSupportURL.appendingPathComponent(archivedDirectoryName, isDirectory: true)
            for url in storeFamily(named: liveStoreName, in: archiveURL, fileManager: fileManager) {
                do {
                    try fileManager.moveItem(at: url, to: appSupportURL.appendingPathComponent(url.lastPathComponent))
                } catch {
                    restoredAll = false
                    log.error("Rollback couldn't move \(url.lastPathComponent, privacy: .public) back: \(error.localizedDescription, privacy: .public)")
                }
            }
            if restoredAll {
                try? fileManager.removeItem(at: archiveURL)
            }
        }
        userDefaults.removeObject(forKey: lastRestoredClientCountKey)
        recordFailure(.unopenable, userDefaults: userDefaults)
        return restoredAll
    }

    @discardableResult
    private static func recordFailure(_ reason: FailureReason, userDefaults: UserDefaults) -> Outcome {
        userDefaults.set(reason.rawValue, forKey: lastRestoreFailureKey)
        return .failed(reason)
    }

    private static func restore(directoryName: String, appSupportURL: URL, fileManager: FileManager) throws -> Outcome {
        guard isSafeDirectoryName(directoryName), Kind(directoryName: directoryName) != nil else {
            throw RestoreError.invalidBackupName(directoryName)
        }
        let backupDirectory = appSupportURL.appendingPathComponent(directoryName, isDirectory: true)
        guard let backupStore = backupStoreURL(in: backupDirectory, fileManager: fileManager) else {
            throw RestoreError.missingBackupStore(directoryName)
        }
        guard let clientCount = StoreFileMigration.clientRowCount(in: backupStore), clientCount > 0 else {
            throw RestoreError.emptyBackup(directoryName)
        }

        // 1. Move the live store aside. Never delete it: the user may want it back.
        let liveFamily = storeFamily(named: liveStoreName, in: appSupportURL, fileManager: fileManager)
        var archive: (name: String, url: URL, moved: [(from: URL, to: URL)])?
        if !liveFamily.isEmpty {
            let archiveName = Kind.preRestore.directoryPrefix + timestamp()
            let archiveURL = appSupportURL.appendingPathComponent(archiveName, isDirectory: true)
            try fileManager.createDirectory(at: archiveURL, withIntermediateDirectories: true)
            var moved: [(from: URL, to: URL)] = []
            do {
                for url in liveFamily {
                    let destination = archiveURL.appendingPathComponent(url.lastPathComponent)
                    try fileManager.moveItem(at: url, to: destination)
                    moved.append((url, destination))
                }
            } catch {
                moveBack(moved, fileManager: fileManager)
                try? fileManager.removeItem(at: archiveURL)
                throw error
            }
            try? readme(
                reason: "Pawtrackr moved this store aside while restoring \(directoryName).",
                files: moved.map(\.to.lastPathComponent)
            ).write(to: archiveURL.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)
            archive = (archiveName, archiveURL, moved)
        }

        // 2. Copy the backup into place: the database plus any un-checkpointed WAL.
        //    The -shm index is rebuilt by SQLite, so a stale copy is left behind.
        var copied: [URL] = []
        do {
            let liveStore = appSupportURL.appendingPathComponent(liveStoreName)
            try fileManager.copyItem(at: backupStore, to: liveStore)
            copied.append(liveStore)

            let backupWAL = URL(fileURLWithPath: backupStore.path + "-wal")
            if let size = try? fileManager.attributesOfItem(atPath: backupWAL.path)[.size] as? Int, size > 0 {
                let liveWAL = appSupportURL.appendingPathComponent(liveStoreName + "-wal")
                try fileManager.copyItem(at: backupWAL, to: liveWAL)
                copied.append(liveWAL)
            }
        } catch {
            copied.forEach { try? fileManager.removeItem(at: $0) }
            if let archive {
                moveBack(archive.moved, fileManager: fileManager)
                try? fileManager.removeItem(at: archive.url)
            }
            throw error
        }

        // 3. Photos and logos live next to the store (@Attribute(.externalStorage)).
        //    Bring back any the backup carries; never overwrite existing files.
        let backupSupport = backupDirectory.appendingPathComponent(supportDirectoryName(forStoreNamed: backupStore.lastPathComponent))
        let liveSupport = appSupportURL.appendingPathComponent(supportDirectoryName(forStoreNamed: liveStoreName))
        mergeMissingFiles(from: backupSupport, into: liveSupport, fileManager: fileManager)

        log.info("Restored \(clientCount) clients from \(directoryName, privacy: .public).")
        return .restored(directoryName: directoryName, clientCount: clientCount, archivedDirectoryName: archive?.name)
    }

    // MARK: - Helpers

    /// Backup folder names end with the UTC time they were made
    /// ("RecoveryBackup-2026-09-26T02-50-49Z"). That beats filesystem dates,
    /// which reset whenever a folder is copied — including when a device backup
    /// is restored onto a new phone.
    static func timestamp(fromDirectoryName name: String) -> Date? {
        let stampLength = "2026-09-26T02-50-49Z".count
        guard name.count >= stampLength else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss'Z'"
        return formatter.date(from: String(name.suffix(stampLength)))
    }

    /// `.Pawtrackr_SUPPORT` for `Pawtrackr.store` — where Core Data keeps
    /// external-storage blobs.
    static func supportDirectoryName(forStoreNamed storeName: String) -> String {
        let base = storeName.hasSuffix(".store") ? String(storeName.dropLast(".store".count)) : storeName
        return "." + base + "_SUPPORT"
    }

    static func mergeMissingFiles(from source: URL, into destination: URL, fileManager: FileManager) {
        guard let enumerator = fileManager.enumerator(at: source, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return
        }
        let sourcePath = source.standardizedFileURL.path
        for case let url as URL in enumerator {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard !isDirectory else { continue }
            let relative = String(url.standardizedFileURL.path.dropFirst(sourcePath.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let target = destination.appendingPathComponent(relative)
            guard !fileManager.fileExists(atPath: target.path) else { continue }
            do {
                try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.copyItem(at: url, to: target)
            } catch {
                log.error("Couldn't restore external file \(relative, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private static func backupStoreURL(in directory: URL, fileManager: FileManager) -> URL? {
        backupStoreNames
            .map { directory.appendingPathComponent($0) }
            .first { fileManager.fileExists(atPath: $0.path) }
    }

    /// `Pawtrackr.store`, `-wal`, `-shm` — not the `.Pawtrackr_SUPPORT` folder,
    /// which the restored store may still reference.
    private static func storeFamily(named baseName: String, in directory: URL, fileManager: FileManager) -> [URL] {
        let names = [baseName, baseName + "-wal", baseName + "-shm"]
        return names
            .map { directory.appendingPathComponent($0) }
            .filter { fileManager.fileExists(atPath: $0.path) }
    }

    private static func moveBack(_ moved: [(from: URL, to: URL)], fileManager: FileManager) {
        for item in moved.reversed() {
            try? fileManager.moveItem(at: item.to, to: item.from)
        }
    }

    private static func isSafeDirectoryName(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("/") && !name.contains("..")
    }

    private static func defaultAppSupportURL(fileManager: FileManager) -> URL? {
        try? fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    }

    private static func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
    }

    private static func readme(reason: String, files: [String]) -> String {
        [
            "Pawtrackr store backup",
            "Created: \(Date().formatted(date: .complete, time: .standard))",
            "Reason: \(reason)",
            "Files:",
            files.isEmpty ? "- none" : files.map { "- \($0)" }.joined(separator: "\n")
        ].joined(separator: "\n")
    }
}
