import XCTest
import CloudKit
import CoreData
@testable import Pawtrackr

/// The rules between the upload record and what the groomer sees: when a
/// failure goes red, what waits for the account check, what carries over
/// from older builds and what support gets. NSPersistentCloudKitContainer
/// events can't be constructed, so the monitor's decisions live here.
final class SyncStatusPolicyTests: XCTestCase {
    private typealias Policy = SyncStatusPolicy
    private typealias Health = SyncHealthReducer.ExportHealth

    private let origin = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        suiteName = "SyncStatusPolicyTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    private func minute(_ offset: Double) -> Date {
        origin.addingTimeInterval(offset * 60)
    }

    private func health(
        failures: Int,
        since: Double,
        disposition: SyncHealthReducer.FailureDisposition?
    ) -> Health {
        Health(
            consecutiveFailures: failures,
            firstFailureAt: minute(since),
            lastFailureAt: minute(since),
            lastFailureDisposition: disposition,
            lastFailureCode: nil
        )
    }

    // MARK: - Red or not

    func testRejectionsAreSevereAtOnceEvenOffline() {
        for disposition in [SyncHealthReducer.FailureDisposition.schemaRejected, .limitExceeded, .setupFailedWhileSignedIn, .userDeletedZone] {
            let record = health(failures: 1, since: 0, disposition: disposition)
            XCTAssertTrue(Policy.isSevereFailure(record, isOnline: true, now: minute(1)), "\(disposition)")
            XCTAssertTrue(Policy.isSevereFailure(record, isOnline: false, now: minute(1)), "\(disposition)")
        }
    }

    func testOneOrTwoRetryableFailuresStayAWarning() {
        for disposition in [SyncHealthReducer.FailureDisposition.transient, .unknown] {
            XCTAssertFalse(Policy.isSevereFailure(health(failures: 1, since: 0, disposition: disposition), isOnline: true, now: minute(5)))
            XCTAssertFalse(Policy.isSevereFailure(health(failures: 2, since: 0, disposition: disposition), isOnline: true, now: minute(5)))
        }
        XCTAssertFalse(Policy.isSevereFailure(health(failures: 1, since: 0, disposition: nil), isOnline: true, now: minute(5)))
    }

    func testThreeFailuresInARowGoRedOnlyWhileOnline() {
        let streak = health(failures: 3, since: 0, disposition: .transient)
        XCTAssertTrue(Policy.isSevereFailure(streak, isOnline: true, now: minute(5)))
        // Someone on a plane isn't being rejected; don't tell her not to delete the app.
        XCTAssertFalse(Policy.isSevereFailure(streak, isOnline: false, now: minute(5)))
    }

    func testAnHourOfObservedFailuresGoesRedOnlyWhileOnline() {
        var failing = health(failures: 2, since: 0, disposition: .unknown)
        failing.lastFailureAt = minute(59)
        XCTAssertFalse(Policy.isSevereFailure(failing, isOnline: true, now: minute(90)))
        failing.lastFailureAt = minute(60)
        XCTAssertTrue(Policy.isSevereFailure(failing, isOnline: true, now: minute(60)))
        XCTAssertFalse(Policy.isSevereFailure(failing, isOnline: false, now: minute(120)))
    }

    /// Restored at launch from last night: nothing has been retried yet.
    func testALoneFailureNeverAgesIntoRed() {
        let lone = health(failures: 1, since: 0, disposition: .transient)
        XCTAssertFalse(Policy.isSevereFailure(lone, isOnline: true, now: minute(12 * 60)))
    }

    func testNoFailureIsNeverSevere() {
        XCTAssertFalse(Policy.isSevereFailure(Health(), isOnline: true, now: minute(600)))
    }

    func testStorageAndAccountFailuresKeepTheirOwnBanner() {
        for disposition in [SyncHealthReducer.FailureDisposition.quotaExceeded, .notAuthenticated, .accountTemporarilyUnavailable] {
            let streak = health(failures: 5, since: 0, disposition: disposition)
            XCTAssertTrue(Policy.isSevereFailure(streak, isOnline: true, now: minute(120)))
            XCTAssertFalse(
                Policy.showsUploadRejectionBanner(
                    status: .failing(since: minute(0), disposition: disposition),
                    health: streak,
                    isOnline: true,
                    now: minute(120)
                ),
                "\(disposition) would hide the banner that tells the groomer how to fix it"
            )
        }
    }

    func testRejectionBannerNeedsAFailingStatus() {
        let rejected = health(failures: 1, since: 0, disposition: .schemaRejected)
        XCTAssertTrue(Policy.showsUploadRejectionBanner(
            status: .failing(since: minute(0), disposition: .schemaRejected),
            health: rejected,
            isOnline: true,
            now: minute(1)
        ))
        // Signed out or local-only outranks failing in BackupStatus, and has its own banner.
        XCTAssertFalse(Policy.showsUploadRejectionBanner(status: .signedOut, health: rejected, isOnline: true, now: minute(1)))
        XCTAssertFalse(Policy.showsUploadRejectionBanner(status: .localOnly, health: rejected, isOnline: true, now: minute(1)))
    }

    // MARK: - Pending grace

    func testPendingChangesWarnOnlyPastTheGracePeriod() {
        XCTAssertFalse(Policy.isPendingPastGrace(since: minute(0), now: minute(4.9)))
        XCTAssertTrue(Policy.isPendingPastGrace(since: minute(0), now: minute(5)))
    }

    func testFirstSaveOnANeverUploadedDeviceStillGetsTheGracePeriod() {
        var reducer = SyncHealthReducer()
        reducer.recordLocalChange(at: minute(0))
        let conditions = SyncHealthReducer.Conditions(account: .available, isOnline: true)

        // Honest status: nothing is backed up. It just isn't a warning yet.
        guard case .notBackedUp(let since?) = reducer.backupStatus(conditions: conditions, now: minute(1)) else {
            return XCTFail("A never-uploaded device with a local change is not backed up")
        }
        XCTAssertFalse(Policy.isPendingPastGrace(since: since, now: minute(1)))
        XCTAssertTrue(Policy.isPendingPastGrace(since: since, now: minute(6)))
    }

    // MARK: - Never uploaded

    func testNeverUploadedWarningWaitsForClientsAndTenMinutesSignedIn() {
        let fresh = SyncHealthReducer.State()
        XCTAssertFalse(Policy.showsNeverUploadedWarning(state: fresh, knownClientCount: 0, accountAvailableSince: minute(0), now: minute(60)))
        XCTAssertFalse(Policy.showsNeverUploadedWarning(state: fresh, knownClientCount: 12, accountAvailableSince: nil, now: minute(60)))
        XCTAssertFalse(Policy.showsNeverUploadedWarning(state: fresh, knownClientCount: 12, accountAvailableSince: minute(0), now: minute(9)))
        XCTAssertTrue(Policy.showsNeverUploadedWarning(state: fresh, knownClientCount: 12, accountAvailableSince: minute(0), now: minute(10)))

        var uploaded = fresh
        uploaded.everExportedSuccessfully = true
        XCTAssertFalse(Policy.showsNeverUploadedWarning(state: uploaded, knownClientCount: 12, accountAvailableSince: minute(0), now: minute(60)))

        var failing = fresh
        failing.exportHealth = health(failures: 1, since: 1, disposition: .schemaRejected)
        XCTAssertFalse(
            Policy.showsNeverUploadedWarning(state: failing, knownClientCount: 12, accountAvailableSince: minute(0), now: minute(60)),
            "A failure already says more than 'nothing has uploaded'"
        )
    }

    // MARK: - Held for the account check

    func testSetup134400WaitsForTheAccountCheck() {
        let setup = NSError(domain: NSCocoaErrorDomain, code: 134400)
        let wrapped = NSError(domain: NSCocoaErrorDomain, code: 134060, userInfo: [NSUnderlyingErrorKey: setup])
        XCTAssertTrue(Policy.needsAccountStatus(setup))
        XCTAssertTrue(Policy.needsAccountStatus(wrapped))

        XCTAssertFalse(Policy.needsAccountStatus(CKError(.networkFailure)))
        XCTAssertFalse(Policy.needsAccountStatus(CKError(.quotaExceeded)))
        XCTAssertFalse(Policy.needsAccountStatus(NSError(domain: NSCocoaErrorDomain, code: 134110)))
    }

    func testClassificationConvertsToTheReducersDisposition() {
        let quota = SyncErrorClassifier.classify(CKError(.quotaExceeded), accountAvailable: true)
        XCTAssertEqual(Policy.failureDisposition(for: quota), .quotaExceeded)

        let signedOutSetup = SyncErrorClassifier.classify(NSError(domain: NSCocoaErrorDomain, code: 134400), accountAvailable: false)
        XCTAssertEqual(Policy.failureDisposition(for: signedOutSetup), .notAuthenticated)

        let signedInSetup = SyncErrorClassifier.classify(NSError(domain: NSCocoaErrorDomain, code: 134400), accountAvailable: true)
        XCTAssertEqual(Policy.failureDisposition(for: signedInSetup), .setupFailedWhileSignedIn)
    }

    func testEventTypesMapToReducerKinds() {
        XCTAssertEqual(Policy.reducerKind(for: .setup), .setup)
        XCTAssertEqual(Policy.reducerKind(for: .import), .import)
        XCTAssertEqual(Policy.reducerKind(for: .export), .export)
    }

    // MARK: - Status deadlines

    func testNextDeadlineIsTheEarliestFutureThreshold() {
        let failing = health(failures: 1, since: 0, disposition: .transient)
        let deadline = Policy.nextStatusDeadline(
            oldestUncoveredLocalChange: minute(2),
            health: failing,
            accountAvailableSince: minute(1),
            now: minute(3)
        )
        XCTAssertEqual(deadline, minute(2).addingTimeInterval(SyncHealthReducer.gracePeriod))

        // Past thresholds don't count.
        let later = Policy.nextStatusDeadline(
            oldestUncoveredLocalChange: minute(2),
            health: failing,
            accountAvailableSince: minute(1),
            now: minute(30)
        )
        XCTAssertEqual(later, minute(60))
    }

    func testNoDeadlineWhenNothingCanChangeWithTime() {
        XCTAssertNil(Policy.nextStatusDeadline(oldestUncoveredLocalChange: nil, health: Health(), accountAvailableSince: nil, now: minute(0)))
        XCTAssertNil(Policy.nextStatusDeadline(
            oldestUncoveredLocalChange: minute(0),
            health: Health(),
            accountAvailableSince: minute(0),
            now: minute(600)
        ))
    }

    // MARK: - Failure log

    func testFailureLogKeepsTheNewestTwenty() {
        var log: [SyncFailureRecord] = []
        for index in 0..<25 {
            log = Policy.appending(
                SyncFailureRecord(occurredAt: minute(Double(index)), kind: .exportToCloud, disposition: "transient", code: "CKError.4", serverMessage: nil),
                to: log
            )
        }
        XCTAssertEqual(log.count, Policy.failureLogLimit)
        XCTAssertEqual(log.first?.occurredAt, minute(24))
        XCTAssertEqual(log.last?.occurredAt, minute(5))
    }

    func testFailureRecordRoundTripsThroughJSON() throws {
        let record = SyncFailureRecord(
            occurredAt: minute(1),
            kind: .setup,
            disposition: "setupFailedWhileSignedIn",
            code: "NSCocoaErrorDomain.134400",
            serverMessage: "Cannot create new type CD_LoyaltyConfig in production schema"
        )
        let decoded = try JSONDecoder().decode([SyncFailureRecord].self, from: JSONEncoder().encode([record]))
        XCTAssertEqual(decoded, [record])
    }

    // MARK: - Pre-1.0.3 keys

    func testNothingFromOlderBuildsMeansNothingClaimed() {
        let state = Policy.migratedState(from: .init(), now: minute(0))
        XCTAssertEqual(state, SyncHealthReducer.State())
    }

    func testOldExportDateCarriesOverAsAnUpload() {
        let state = Policy.migratedState(
            from: .init(lastExportDate: minute(10), lastImportDate: minute(20)),
            now: minute(30)
        )
        XCTAssertTrue(state.everExportedSuccessfully)
        XCTAssertEqual(state.lastSuccessfulExportStartedAt, minute(10))
        XCTAssertEqual(state.lastSuccessfulExportEndedAt, minute(10))
        XCTAssertEqual(state.lastImportEndedAt, minute(20))

        let reducer = SyncHealthReducer(state: state)
        XCTAssertEqual(
            reducer.backupStatus(conditions: .init(account: .available, isOnline: true), now: minute(40)),
            .backedUp(asOf: minute(10))
        )
    }

    func testOldImportDateAloneIsNotABackup() {
        let state = Policy.migratedState(from: .init(lastImportDate: minute(20)), now: minute(30))
        XCTAssertFalse(state.everExportedSuccessfully)
        XCTAssertNil(state.lastSuccessfulExportEndedAt)
    }

    func testOldPendingChangeAfterTheLastExportStaysPending() {
        let state = Policy.migratedState(
            from: .init(lastExportDate: minute(10), pendingLocalChangeCount: 2, pendingLocalChangeDate: minute(15)),
            now: minute(30)
        )
        XCTAssertEqual(state.pendingLocalChangeDate, minute(15))
        let reducer = SyncHealthReducer(state: state)
        XCTAssertEqual(
            reducer.backupStatus(conditions: .init(account: .available, isOnline: true), now: minute(30)),
            .notBackedUp(localChangesSince: minute(15))
        )
    }

    func testOldQuotaFlagCarriesOverAsAFailingUpload() {
        let state = Policy.migratedState(
            from: .init(lastExportDate: minute(10), lastAttemptDate: minute(12), quotaExceeded: true),
            now: minute(30)
        )
        XCTAssertTrue(state.exportHealth.isFailing)
        XCTAssertEqual(state.exportHealth.lastFailureDisposition, .quotaExceeded)
        XCTAssertEqual(state.exportHealth.firstFailureAt, minute(12))
        XCTAssertEqual(state.exportHealth.lastFailureCode, "CKError.\(CKError.Code.quotaExceeded.rawValue)")

        // An attempt date older than the last export can't date the failure.
        let undated = Policy.migratedState(
            from: .init(lastExportDate: minute(10), lastAttemptDate: minute(5), quotaExceeded: true),
            now: minute(30)
        )
        XCTAssertEqual(undated.exportHealth.firstFailureAt, minute(30))
    }

    func testMigrationReadsTheOldKeys() {
        defaults.set(minute(10), forKey: "cloudkit.lastExportDate")
        defaults.set(minute(20), forKey: "cloudkit.lastImportDate")
        defaults.set(3, forKey: "cloudkit.pendingLocalChangeCount")
        defaults.set(minute(25), forKey: "cloudkit.pendingLocalChangeDate")
        defaults.set(true, forKey: "cloudkit.quotaExceeded")

        let legacy = CloudKitMonitor.legacySyncDefaults(defaults: defaults)
        XCTAssertEqual(legacy.lastExportDate, minute(10))
        XCTAssertEqual(legacy.lastImportDate, minute(20))
        XCTAssertEqual(legacy.pendingLocalChangeCount, 3)
        XCTAssertEqual(legacy.pendingLocalChangeDate, minute(25))
        XCTAssertTrue(legacy.quotaExceeded)
        XCTAssertNil(CloudKitMonitor.persistedSyncHealthState(defaults: defaults))
    }

    func testPersistedStateUsesTheVersionedKey() throws {
        var reducer = SyncHealthReducer()
        reducer.apply(.succeeded(.export, startedAt: minute(1), endedAt: minute(2)))
        defaults.set(try JSONEncoder().encode(reducer.state), forKey: "cloudkit.syncHealth.v1")

        XCTAssertEqual(CloudKitMonitor.persistedSyncHealthState(defaults: defaults), reducer.state)
    }

    // MARK: - Reports

    func testEvidenceSaysNeverWhenNothingUploaded() {
        let lines = CloudKitMonitor.persistedUploadEvidenceLines(defaults: defaults)
        XCTAssertTrue(lines.contains("Last confirmed iCloud upload from this device: never"))
        XCTAssertTrue(lines.contains("Ever uploaded from this device: no"))
        XCTAssertTrue(lines.contains("Local-only fallback: no"))
        XCTAssertTrue(lines.contains("Recent iCloud failures (0):"))
    }

    func testEvidenceCarriesTheStreakFallbackAndFailureLog() throws {
        var reducer = SyncHealthReducer()
        reducer.apply(.succeeded(.export, startedAt: minute(1), endedAt: minute(2)))
        reducer.apply(.failed(.export, startedAt: minute(9), endedAt: minute(10), disposition: .schemaRejected, code: "CKError.15"))
        defaults.set(try JSONEncoder().encode(reducer.state), forKey: "cloudkit.syncHealth.v1")
        let failure = SyncFailureRecord(
            occurredAt: minute(10),
            kind: .exportToCloud,
            disposition: "schemaRejected",
            code: "CKError.15",
            serverMessage: "Cannot create new type CD_LoyaltyConfig in production schema"
        )
        defaults.set(try JSONEncoder().encode([failure]), forKey: "cloudkit.failureLog.v1")
        defaults.set(true, forKey: AppStoreBootstrap.cloudKitFallbackActiveKey)
        defaults.set(minute(0), forKey: AppStoreBootstrap.cloudKitFallbackSinceKey)

        let report = CloudKitMonitor.persistedUploadEvidenceLines(defaults: defaults).joined(separator: "\n")
        XCTAssertTrue(report.contains("Ever uploaded from this device: yes"))
        XCTAssertTrue(report.contains("1 in a row, cause schemaRejected [CKError.15]"))
        XCTAssertTrue(report.contains("Local-only fallback: yes, since \(minute(0).formatted())"))
        XCTAssertTrue(report.contains("Recent iCloud failures (1):"))
        XCTAssertTrue(report.contains("schemaRejected [CKError.15]: Cannot create new type CD_LoyaltyConfig"))
    }

    // MARK: - Recovery screen

    func testRecoveryWarnsUnlessARecentUploadStandsUnchallenged() {
        var reducer = SyncHealthReducer()
        XCTAssertTrue(Policy.lacksRecentUpload(reducer.state, now: minute(0)), "Never uploaded")

        reducer.apply(.succeeded(.export, startedAt: minute(0), endedAt: minute(1)))
        XCTAssertFalse(Policy.lacksRecentUpload(reducer.state, now: minute(60)))
        XCTAssertFalse(Policy.lacksRecentUpload(reducer.state, now: minute(1 + 24 * 60)), "Exactly a day old still counts")
        XCTAssertTrue(Policy.lacksRecentUpload(reducer.state, now: minute(2 + 24 * 60)), "Older than a day")

        reducer.apply(.failed(.export, startedAt: minute(5), endedAt: minute(6), disposition: .transient, code: nil))
        XCTAssertTrue(Policy.lacksRecentUpload(reducer.state, now: minute(10)), "A failure since the upload")
    }

    func testRecoveryWarnsAboutEditsNoUploadCoveredAndLocalOnly() {
        var reducer = SyncHealthReducer()
        reducer.apply(.succeeded(.export, startedAt: minute(0), endedAt: minute(1)))
        XCTAssertFalse(Policy.lacksRecentUpload(reducer.state, now: minute(60)))
        XCTAssertTrue(Policy.lacksRecentUpload(reducer.state, isLocalOnlyFallback: true, now: minute(60)), "Local-only since")

        reducer.recordLocalChange(at: minute(30))
        XCTAssertTrue(Policy.lacksRecentUpload(reducer.state, now: minute(60)), "A checkout after the last upload")

        reducer.apply(.succeeded(.export, startedAt: minute(31), endedAt: minute(32)))
        XCTAssertFalse(Policy.lacksRecentUpload(reducer.state, now: minute(60)), "Covered by the next upload")
    }

    func testRecoveryReadsTheOldKeysWhenNoRecordWasWritten() {
        // A 1.0.2 store that won't open never had the 1.0.3 record written.
        defaults.set(minute(30), forKey: "cloudkit.lastExportDate")

        let state = CloudKitMonitor.persistedOrMigratedSyncHealth(defaults: defaults, now: minute(40))
        XCTAssertEqual(state.lastSuccessfulExportEndedAt, minute(30))
        XCTAssertFalse(Policy.lacksRecentUpload(state, now: minute(40)))
    }

    // MARK: - Evidence kept through a reset

    func testPreservingEvidenceCopiesWhatAResetClears() throws {
        var reducer = SyncHealthReducer()
        reducer.apply(.succeeded(.export, startedAt: minute(1), endedAt: minute(2)))
        reducer.apply(.failed(.export, startedAt: minute(9), endedAt: minute(10), disposition: .schemaRejected, code: "CKError.15"))
        let record = try JSONEncoder().encode(reducer.state)
        defaults.set(record, forKey: "cloudkit.syncHealth.v1")
        defaults.set(minute(2), forKey: "cloudkit.lastExportDate")
        defaults.set(minute(3), forKey: "cloudkit.lastImportDate")
        defaults.set(true, forKey: "cloudkit.firstSyncCompleted")
        defaults.set(true, forKey: AppStoreBootstrap.cloudKitFallbackActiveKey)
        defaults.set(minute(4), forKey: AppStoreBootstrap.cloudKitFallbackSinceKey)
        defaults.set(try JSONEncoder().encode((0..<12).map { event(at: minute(Double(20 - $0)), message: "event \($0)") }), forKey: "cloudkit.syncEvents")

        CloudKitMonitor.preserveSyncEvidenceBeforeReset(defaults: defaults, now: minute(30))

        XCTAssertEqual(defaults.data(forKey: "cloudkit.preReset.syncHealth.v1"), record, "Copied byte for byte")
        XCTAssertEqual(defaults.object(forKey: "cloudkit.preReset.lastExportDate") as? Date, minute(2))
        XCTAssertEqual(defaults.object(forKey: "cloudkit.preReset.lastImportDate") as? Date, minute(3))
        XCTAssertTrue(defaults.bool(forKey: "cloudkit.preReset.firstSyncCompleted"))
        XCTAssertTrue(defaults.bool(forKey: "cloudkit.preReset.fallbackActive"))
        XCTAssertEqual(defaults.object(forKey: "cloudkit.preReset.fallbackSince") as? Date, minute(4))
        XCTAssertEqual(defaults.object(forKey: "cloudkit.preReset.capturedAt") as? Date, minute(30))
        let kept = try JSONDecoder().decode(
            [CloudKitMonitor.SyncEvent].self,
            from: try XCTUnwrap(defaults.data(forKey: "cloudkit.preReset.syncEvents"))
        )
        XCTAssertEqual(kept.map(\.message), (0..<10).map { "event \($0)" }, "The newest ten")

        // What the reset then clears no longer matters to the report.
        for key in ["cloudkit.syncHealth.v1", "cloudkit.lastExportDate", "cloudkit.lastImportDate", "cloudkit.firstSyncCompleted", "cloudkit.syncEvents"] {
            defaults.removeObject(forKey: key)
        }
        defaults.removeObject(forKey: AppStoreBootstrap.cloudKitFallbackActiveKey)

        let lines = CloudKitMonitor.persistedUploadEvidenceLines(defaults: defaults)
        XCTAssertTrue(lines.contains("Last confirmed iCloud upload from this device: never"))
        XCTAssertTrue(lines.contains("Before the last reset or restore (\(minute(30).formatted())):"))
        XCTAssertTrue(lines.contains("- Ever uploaded from this device: yes"))
        XCTAssertTrue(lines.contains { $0.hasPrefix("- Upload health: failing since") && $0.hasSuffix("cause schemaRejected [CKError.15]") })
        XCTAssertTrue(lines.contains("- cloudkit.lastExportDate: \(minute(2).formatted()), cloudkit.lastImportDate: \(minute(3).formatted())"))
        XCTAssertTrue(lines.contains("- First iCloud sync finished: yes"))
        XCTAssertTrue(lines.contains("- Local-only fallback: yes, since \(minute(4).formatted())"))
        XCTAssertTrue(lines.contains("- Sync events kept (10):"))
        XCTAssertTrue(lines.contains { $0.hasPrefix("- ") && $0.hasSuffix("Export Failed: event 0 [CKError.15]") })
        XCTAssertFalse(lines.contains { $0.hasPrefix("  ") }, "One level only: SupportService indents these itself")
    }

    func testPreservingEvidenceDropsAnOlderSnapshotsLeftovers() {
        defaults.set(minute(1), forKey: "cloudkit.preReset.fallbackSince")
        defaults.set(minute(1), forKey: "cloudkit.preReset.lastExportDate")

        CloudKitMonitor.preserveSyncEvidenceBeforeReset(defaults: defaults, now: minute(30))

        XCTAssertNil(defaults.object(forKey: "cloudkit.preReset.fallbackSince"))
        XCTAssertNil(defaults.object(forKey: "cloudkit.preReset.lastExportDate"))
        let lines = CloudKitMonitor.persistedUploadEvidenceLines(defaults: defaults)
        XCTAssertTrue(lines.contains("- Last confirmed iCloud upload from this device: never"))
        XCTAssertTrue(lines.contains("- Local-only fallback: no"))
    }

    func testRecentSyncEventLinesKeepTheNewestTen() throws {
        XCTAssertEqual(CloudKitMonitor.recentSyncEventLines(defaults: defaults), ["Recent sync events (0):", "- none"])

        defaults.set(try JSONEncoder().encode((0..<12).map { event(at: minute(Double(20 - $0)), message: "event \($0)") }), forKey: "cloudkit.syncEvents")
        let lines = CloudKitMonitor.recentSyncEventLines(defaults: defaults)
        XCTAssertEqual(lines.first, "Recent sync events (10):")
        XCTAssertEqual(lines.count, 11)
        XCTAssertTrue(lines[1].hasSuffix("event 0 [CKError.15]"))
    }

    private func event(at date: Date, message: String) -> CloudKitMonitor.SyncEvent {
        CloudKitMonitor.SyncEvent(
            id: UUID(),
            kind: .exportToCloud,
            status: .failed,
            startedAt: date,
            endedAt: date,
            message: message,
            deviceID: UUID(),
            errorCode: "CKError.15"
        )
    }

    // MARK: - Copy

    func testEveryFailureMessageKeyExistsInEnglish() {
        let dispositions: [SyncErrorClassifier.Disposition] = [
            .transient,
            .userActionable(.quotaExceeded),
            .userActionable(.notAuthenticated),
            .userActionable(.accountTemporarilyUnavailable),
            .userActionable(.userDeletedZone),
            .schemaRejected,
            .limitExceeded,
            .setupFailedWhileSignedIn,
            .unknown
        ]
        let samples = dispositions.map {
            SyncErrorClassifier.Classification(disposition: $0, innermostDomain: CKError.errorDomain, innermostCode: 0, serverMessage: nil)
        } + [
            SyncErrorClassifier.Classification(
                disposition: .transient,
                innermostDomain: CKError.errorDomain,
                innermostCode: CKError.Code.networkFailure.rawValue,
                serverMessage: nil
            )
        ]

        for classification in samples {
            guard let key = classification.userMessageKey else {
                XCTFail("\(classification.disposition) has nothing to tell the groomer")
                continue
            }
            let english = Bundle.main.localizedString(forKey: key, value: "MISSING", table: nil)
            XCTAssertNotEqual(english, "MISSING", "\(key) is missing from en.lproj")
            XCTAssertEqual(SyncFailureCopy.message(for: classification), english, "\(classification.disposition)")
        }
    }

    func testOnlyAnAllTransientFailurePromisesARetry() {
        let partial = SyncErrorClassifier.Classification(disposition: .unknown, innermostDomain: CKError.errorDomain, innermostCode: 2, serverMessage: nil)
        let retry = Bundle.main.localizedString(forKey: "cloudkit.error.partial", value: nil, table: nil)
        XCTAssertNotEqual(SyncFailureCopy.message(for: partial), retry)
        XCTAssertNil(SyncFailureCopy.message(for: .benign, isNetwork: false))
    }
}

/// The telemetry seam: only failures retrying can't fix, at most once a day
/// each, and never CloudKit's own wording.
@MainActor
final class SyncFailureReportingTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var sent: [(String, [String: String])] = []
    private var now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    override func setUp() async throws {
        suiteName = "SyncFailureReportingTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        sent = []
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    private func makeReporter() -> TelemetrySyncFailureReporter {
        TelemetrySyncFailureReporter(
            defaults: defaults,
            now: { [unowned self] in self.now },
            appVersion: "1.0.3-4",
            osVersion: "iOS 26.5.0",
            send: { [unowned self] event, parameters in self.sent.append((event, parameters)) }
        )
    }

    private func classification(_ disposition: SyncErrorClassifier.Disposition, code: Int = 12) -> SyncErrorClassifier.Classification {
        SyncErrorClassifier.Classification(
            disposition: disposition,
            innermostDomain: CKError.errorDomain,
            innermostCode: code,
            serverMessage: "Cannot create new type CD_LoyaltyConfig in production schema"
        )
    }

    func testRejectionIsReportedOncePerDispositionPerDay() {
        let reporter = makeReporter()
        XCTAssertTrue(reporter.reportIfNeeded(classification(.schemaRejected)))
        XCTAssertFalse(reporter.reportIfNeeded(classification(.schemaRejected)))

        // A different rejection has its own allowance.
        XCTAssertTrue(reporter.reportIfNeeded(classification(.limitExceeded, code: 27)))

        now = now.addingTimeInterval(23 * 60 * 60)
        XCTAssertFalse(makeReporter().reportIfNeeded(classification(.schemaRejected)), "The limit survives a relaunch")

        now = now.addingTimeInterval(60 * 60)
        XCTAssertTrue(makeReporter().reportIfNeeded(classification(.schemaRejected)))
        XCTAssertEqual(sent.count, 3)
    }

    func testRetryableAndAccountFailuresAreNotReported() {
        let reporter = makeReporter()
        let ignored: [SyncErrorClassifier.Disposition] = [
            .transient, .benign, .unknown, .setupFailedWhileSignedIn,
            .userActionable(.quotaExceeded), .userActionable(.notAuthenticated),
            .userActionable(.accountTemporarilyUnavailable), .userActionable(.userDeletedZone)
        ]
        for disposition in ignored {
            XCTAssertFalse(reporter.reportIfNeeded(classification(disposition)), "\(disposition)")
        }
        XCTAssertTrue(sent.isEmpty)
    }

    func testReportCarriesClassificationAndVersionsButNoServerMessage() throws {
        makeReporter().reportIfNeeded(classification(.schemaRejected))
        let (event, parameters) = try XCTUnwrap(sent.first)
        XCTAssertEqual(event, TelemetrySyncFailureReporter.eventName)
        XCTAssertEqual(parameters, [
            "disposition": "schemaRejected",
            "domain": CKError.errorDomain,
            "code": "12",
            "app_version": "1.0.3-4",
            "os_version": "iOS 26.5.0"
        ])
        XCTAssertFalse(parameters.values.contains { $0.contains("CD_LoyaltyConfig") })
    }

    func testClockSetBackwardsDoesNotSilenceReports() {
        let reporter = makeReporter()
        XCTAssertTrue(reporter.reportIfNeeded(classification(.schemaRejected)))
        now = now.addingTimeInterval(-3 * 24 * 60 * 60)
        XCTAssertTrue(reporter.reportIfNeeded(classification(.schemaRejected)))
    }
}
