//
//  StoreFileLockCoordinator.swift
//  Pawtrackr
//
//  Process-safe coordination for SwiftData/Core Data store-family file work.
//

import Foundation
import OSLog
#if canImport(SQLite3)
import SQLite3
#endif
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Serializes launch-time store-family file work (pre-update backup, legacy
/// move) across threads and processes.
///
/// The lock is a `flock` on `Pawtrackr.store.lock` beside the store, opened
/// with `open(O_CREAT)` so every caller and every process locks the same inode.
/// Every wait is bounded (`timeout`): launch can't hang on a second Mac
/// instance or a debug build that shares the container. On timeout the call
/// throws and the caller skips its file work for this launch; both callers log
/// that and retry on the next launch.
///
/// What it does NOT do: SQLite/Core Data never take this lock, so it gives no
/// protection against an open `ModelContainer` writing the store. Callers must
/// run before any container opens (see CLAUDE.md, "Store-file work").
enum StoreFileLockCoordinator {
    enum LockError: LocalizedError {
        case couldNotCreateLockFile(URL)
        case couldNotAcquireLock(URL, Int32)

        var errorDescription: String? {
            switch self {
            case .couldNotCreateLockFile(let url):
                return "Could not create store lock file at \(url.lastPathComponent)."
            case .couldNotAcquireLock(let url, let code):
                return "Could not acquire store lock \(url.lastPathComponent) (errno \(code))."
            }
        }
    }

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "StoreFileLock")
    static let lockFileName = "Pawtrackr.store.lock"
    /// How long a caller waits for the lock (another thread, or another
    /// process such as a second Mac instance or a debug build sharing the
    /// container) before giving up.
    static let defaultTimeout: TimeInterval = 3
    private static let processLock = NSRecursiveLock()
    /// Lock files this thread already holds, with a nesting count. Only read
    /// or written while `processLock` is held, and `processLock` is recursive,
    /// so a non-zero count always belongs to the current thread.
    nonisolated(unsafe) private static var heldLockDepth: [String: Int] = [:]

    static func withStoreLock<T>(
        in appSupportURL: URL,
        reason: String,
        fileManager: FileManager = .default,
        timeout: TimeInterval = defaultTimeout,
        operation: () throws -> T
    ) throws -> T {
        let lockURL = appSupportURL.appendingPathComponent(lockFileName)
        let deadline = Date().addingTimeInterval(max(0, timeout))

        // In-process: other threads doing store-file work. Bounded, like the
        // cross-process wait below.
        guard processLock.lock(before: deadline) else {
            log.error("Store file lock busy in this process for \(reason, privacy: .public); skipping store-file work this launch.")
            throw LockError.couldNotAcquireLock(lockURL, EWOULDBLOCK)
        }
        defer { processLock.unlock() }

        let key = lockURL.standardizedFileURL.path

        // A nested call on this thread already holds the flock. Taking it
        // again through a second descriptor would conflict with ourselves:
        // flock locks belong to the open file description, not the process.
        if let depth = heldLockDepth[key], depth > 0 {
            heldLockDepth[key] = depth + 1
            defer { heldLockDepth[key] = depth }
            return try operation()
        }

        try fileManager.createDirectory(at: appSupportURL, withIntermediateDirectories: true)

        // open(O_CREAT) keeps the existing inode. FileManager.createFile writes
        // atomically, which swapped in a new inode on every call, so two
        // processes each locked their own file and never excluded each other.
        let descriptor = open(lockURL.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else {
            let code = errno
            log.error("Couldn't open store lock file (errno \(code, privacy: .public)) for \(reason, privacy: .public).")
            throw LockError.couldNotCreateLockFile(lockURL)
        }
        defer { close(descriptor) }

        try acquireExclusiveLock(descriptor, lockURL: lockURL, reason: reason, deadline: deadline)
        defer { flock(descriptor, LOCK_UN) }

        heldLockDepth[key] = 1
        defer { heldLockDepth[key] = nil }

        // No NSFileCoordinator: its wait has no timeout, and with a real flock
        // it added nothing (nothing else coordinates on Application Support).
        log.info("Acquired store file lock for \(reason, privacy: .public)")
        return try operation()
    }

    /// Non-blocking flock with a bounded retry, so a lock held by another
    /// process can never hang launch.
    private static func acquireExclusiveLock(_ descriptor: Int32, lockURL: URL, reason: String, deadline: Date) throws {
        while true {
            if flock(descriptor, LOCK_EX | LOCK_NB) == 0 { return }
            let code = errno
            guard code == EWOULDBLOCK || code == EINTR, Date() < deadline else {
                log.error("Store file lock unavailable (errno \(code, privacy: .public)) for \(reason, privacy: .public); skipping store-file work this launch.")
                throw LockError.couldNotAcquireLock(lockURL, code)
            }
            usleep(50_000)
        }
    }
}

struct SQLiteStoreFileSet: Sendable, Equatable {
    let baseName: String
    let directory: URL
    let files: [URL]
    let supportDirectory: URL?

    var primaryStoreURL: URL {
        directory.appendingPathComponent(baseName)
    }

    var isEmpty: Bool { files.isEmpty && supportDirectory == nil }

    init(baseName: String, directory: URL, fileManager: FileManager = .default) throws {
        self.baseName = baseName
        self.directory = directory
        let contents = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )) ?? []

        self.files = contents
            .filter { url in
                let name = url.lastPathComponent
                return Self.isStoreFamilyMember(name, baseName: baseName)
                    && ((try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true)
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        let support = directory.appendingPathComponent(StoreBackupRestore.supportDirectoryName(forStoreNamed: baseName), isDirectory: true)
        self.supportDirectory = fileManager.fileExists(atPath: support.path) ? support : nil
    }

    static func isStoreFamilyMember(_ fileName: String, baseName: String) -> Bool {
        fileName == baseName
            || fileName.hasPrefix(baseName + "-")
            || fileName.hasPrefix(baseName + "_")
            || fileName.hasPrefix("." + baseName + "-")
            || fileName.hasPrefix("." + baseName + "_")
    }

    func destinationFileName(for fileURL: URL, replacingBaseNameWith newBaseName: String) -> String {
        let fileName = fileURL.lastPathComponent
        if fileName.hasPrefix("." + baseName) {
            return "." + newBaseName + String(fileName.dropFirst(baseName.count + 1))
        }
        if fileName.hasPrefix(baseName) {
            return newBaseName + String(fileName.dropFirst(baseName.count))
        }
        return fileName
    }

    @discardableResult
    func copyFamily(to destinationDirectory: URL, fileManager: FileManager = .default) throws -> [URL] {
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        var copied: [URL] = []
        do {
            for file in files {
                let destination = destinationDirectory.appendingPathComponent(file.lastPathComponent)
                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.removeItem(at: destination)
                }
                try fileManager.copyItem(at: file, to: destination)
                copied.append(destination)
            }
            if let supportDirectory {
                let destination = destinationDirectory.appendingPathComponent(supportDirectory.lastPathComponent, isDirectory: true)
                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.removeItem(at: destination)
                }
                try fileManager.copyItem(at: supportDirectory, to: destination)
                copied.append(destination)
            }
            return copied
        } catch {
            for url in copied {
                try? fileManager.removeItem(at: url)
            }
            throw error
        }
    }

    static func quickCheck(storeURL: URL, fileManager: FileManager = .default) -> Bool {
        guard fileManager.fileExists(atPath: storeURL.path) else { return false }

        #if canImport(SQLite3)
        guard let database = openReadOnlyDatabase(at: storeURL, fileManager: fileManager) else { return false }
        defer { sqlite3_close(database) }

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, "PRAGMA quick_check", -1, &statement, nil) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW,
              let cString = sqlite3_column_text(statement, 0)
        else {
            return false
        }
        return String(cString: cString).localizedCaseInsensitiveCompare("ok") == .orderedSame
        #else
        return true
        #endif
    }

    #if canImport(SQLite3)
    static func openReadOnlyDatabase(at storeURL: URL, fileManager: FileManager = .default) -> OpaquePointer? {
        if let database = openReadable(storeURL.path, flags: SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX) {
            return database
        }

        let walSize = (try? fileManager.attributesOfItem(atPath: storeURL.path + "-wal")[.size] as? Int) ?? 0
        guard walSize == 0,
              let encodedPath = storeURL.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else {
            return nil
        }
        return openReadable(
            "file:\(encodedPath)?immutable=1",
            flags: SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX | SQLITE_OPEN_URI
        )
    }

    private static func openReadable(_ filename: String, flags: Int32) -> OpaquePointer? {
        var database: OpaquePointer?
        guard sqlite3_open_v2(filename, &database, flags, nil) == SQLITE_OK, let database else {
            sqlite3_close(database)
            return nil
        }

        sqlite3_busy_timeout(database, 2_500)

        var statement: OpaquePointer?
        let readable = sqlite3_prepare_v2(database, "SELECT COUNT(*) FROM sqlite_master", -1, &statement, nil) == SQLITE_OK
            && sqlite3_step(statement) == SQLITE_ROW
        sqlite3_finalize(statement)
        guard readable else {
            sqlite3_close(database)
            return nil
        }
        return database
    }
    #endif
}

struct StoreMigrationJournal: Codable, Equatable {
    enum Phase: String, Codable {
        case prepared
        case moving
        case completed
    }

    struct Entry: Codable, Equatable {
        let source: String
        let destination: String
    }

    let id: UUID
    var phase: Phase
    let reason: String
    let createdAt: Date
    let entries: [Entry]

    static let fileName = "StoreMigrationJournal.json"

    static func url(in appSupportURL: URL) -> URL {
        appSupportURL.appendingPathComponent(fileName)
    }

    static func load(from appSupportURL: URL, fileManager: FileManager = .default) -> StoreMigrationJournal? {
        let url = self.url(in: appSupportURL)
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url)
        else {
            return nil
        }
        return try? JSONDecoder().decode(StoreMigrationJournal.self, from: data)
    }

    func save(in appSupportURL: URL) throws {
        let data = try JSONEncoder.storeJournal.encode(self)
        try data.write(to: Self.url(in: appSupportURL), options: [.atomic])
    }

    static func clear(in appSupportURL: URL, fileManager: FileManager = .default) {
        try? fileManager.removeItem(at: url(in: appSupportURL))
    }

    static func recoverIfPossible(in appSupportURL: URL, fileManager: FileManager = .default) {
        guard let journal = load(from: appSupportURL, fileManager: fileManager) else { return }
        if journal.phase == .completed {
            clear(in: appSupportURL, fileManager: fileManager)
            return
        }

        let allSourcesMissing = journal.entries.allSatisfy { !fileManager.fileExists(atPath: appSupportURL.appendingPathComponent($0.source).path) }
        let allDestinationsPresent = journal.entries.allSatisfy { fileManager.fileExists(atPath: appSupportURL.appendingPathComponent($0.destination).path) }
        if allSourcesMissing && allDestinationsPresent {
            clear(in: appSupportURL, fileManager: fileManager)
        }
    }
}

private extension JSONEncoder {
    static var storeJournal: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
