//
//  StoreFileLockCoordinatorTests.swift
//  PawtrackrTests
//
//  Regression: the lock file was recreated with FileManager.createFile on every
//  call, which writes atomically and swaps in a new inode, so a second process
//  locked a different file and nothing was excluded. The blocking LOCK_EX (and
//  the NSFileCoordinator wait) also had no timeout, so launch could hang.
//

import XCTest
import Darwin
@testable import Pawtrackr

final class StoreFileLockCoordinatorTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StoreFileLockCoordinatorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var lockPath: String {
        directory.appendingPathComponent(StoreFileLockCoordinator.lockFileName).path
    }

    private func inode(atPath path: String) throws -> Int {
        try XCTUnwrap(FileManager.default.attributesOfItem(atPath: path)[.systemFileNumber] as? Int)
    }

    /// Another open file description (what a second process would have) must
    /// be refused while the coordinator holds the lock.
    func testHeldLockExcludesAnotherOpenFileDescription() throws {
        var otherResult: Int32 = 0
        var otherErrno: Int32 = 0
        try StoreFileLockCoordinator.withStoreLock(in: directory, reason: "test") {
            let other = open(lockPath, O_RDWR)
            XCTAssertGreaterThanOrEqual(other, 0)
            defer { close(other) }
            otherResult = flock(other, LOCK_EX | LOCK_NB)
            otherErrno = errno
        }
        XCTAssertEqual(otherResult, -1, "A second lock holder must be excluded while the store lock is held.")
        XCTAssertEqual(otherErrno, EWOULDBLOCK)

        // Released afterwards.
        let after = open(lockPath, O_RDWR)
        defer { close(after) }
        XCTAssertEqual(flock(after, LOCK_EX | LOCK_NB), 0)
        flock(after, LOCK_UN)
    }

    func testLockFileKeepsItsInodeAcrossCalls() throws {
        try StoreFileLockCoordinator.withStoreLock(in: directory, reason: "first") {}
        let first = try inode(atPath: lockPath)
        try StoreFileLockCoordinator.withStoreLock(in: directory, reason: "second") {}
        XCTAssertEqual(try inode(atPath: lockPath), first, "Recreating the lock file breaks cross-process exclusion.")
    }

    func testLockHeldElsewhereTimesOutWithoutRunningTheOperation() throws {
        try StoreFileLockCoordinator.withStoreLock(in: directory, reason: "create") {}
        let holder = open(lockPath, O_RDWR)
        XCTAssertGreaterThanOrEqual(holder, 0)
        defer { close(holder) }
        XCTAssertEqual(flock(holder, LOCK_EX | LOCK_NB), 0)
        defer { flock(holder, LOCK_UN) }

        var ran = false
        let started = Date()
        XCTAssertThrowsError(
            try StoreFileLockCoordinator.withStoreLock(in: directory, reason: "blocked", timeout: 0.2) { ran = true }
        ) { error in
            guard case StoreFileLockCoordinator.LockError.couldNotAcquireLock = error else {
                return XCTFail("Unexpected error \(error)")
            }
        }
        XCTAssertFalse(ran)
        XCTAssertLessThan(Date().timeIntervalSince(started), 5, "Launch must not hang on a lock held elsewhere.")
    }

    /// In-process waits are bounded too: another thread doing store-file
    /// work must not hang the caller.
    func testLockHeldByAnotherThreadTimesOut() throws {
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        let lockedDirectory: URL = directory
        Thread.detachNewThread {
            _ = try? StoreFileLockCoordinator.withStoreLock(in: lockedDirectory, reason: "holder") {
                entered.signal()
                release.wait()
            }
            finished.signal()
        }
        XCTAssertEqual(entered.wait(timeout: .now() + 5), .success)

        let started = Date()
        XCTAssertThrowsError(
            try StoreFileLockCoordinator.withStoreLock(in: directory, reason: "blocked", timeout: 0.2) {}
        )
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)

        release.signal()
        XCTAssertEqual(finished.wait(timeout: .now() + 5), .success)
        XCTAssertNoThrow(try StoreFileLockCoordinator.withStoreLock(in: directory, reason: "after", timeout: 0.2) {})
    }

    /// The launch path: when another process holds the lock, the per-build
    /// backup is not made, the store is untouched, and the build is not marked
    /// as backed up, so the next launch makes it.
    func testPerBuildBackupRetriesAfterALockTimeout() throws {
        let suiteName = "StoreFileLockCoordinatorTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = directory.appendingPathComponent("Pawtrackr.store")
        try "current-data".write(to: store, atomically: true, encoding: .utf8)

        let holder = open(lockPath, O_RDWR | O_CREAT, 0o600)
        XCTAssertGreaterThanOrEqual(holder, 0)
        XCTAssertEqual(flock(holder, LOCK_EX | LOCK_NB), 0)

        let blocked = StoreFileMigration.backupStoresForCurrentBuildIfNeeded(
            appSupportURL: directory,
            userDefaults: defaults,
            lockTimeout: 0.2
        )
        XCTAssertEqual(blocked.copiedFiles, 0)
        XCTAssertNil(blocked.backupDirectory)
        let afterBlocked = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertFalse(afterBlocked.contains { $0.hasPrefix("PreMigrationBackup-") })
        XCTAssertEqual(try String(contentsOf: store, encoding: .utf8), "current-data")

        flock(holder, LOCK_UN)
        close(holder)

        let retried = StoreFileMigration.backupStoresForCurrentBuildIfNeeded(
            appSupportURL: directory,
            userDefaults: defaults,
            lockTimeout: 0.2
        )
        XCTAssertEqual(retried.copiedFiles, 1, "The next launch must make the backup the blocked one skipped.")
        XCTAssertNotNil(retried.backupDirectory)
    }

    func testNestedCallOnTheSameThreadDoesNotDeadlock() throws {
        let value = try StoreFileLockCoordinator.withStoreLock(in: directory, reason: "outer", timeout: 0.2) {
            try StoreFileLockCoordinator.withStoreLock(in: directory, reason: "inner", timeout: 0.2) { 42 }
        }
        XCTAssertEqual(value, 42)
    }
}
