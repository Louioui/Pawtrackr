import XCTest
@testable import Pawtrackr

/// The reducer is what stops the app from claiming "backed up" on the strength
/// of imports alone, which can leave a groomer believing iCloud holds clients
/// it never received.
final class SyncHealthReducerTests: XCTestCase {
    private typealias Reducer = SyncHealthReducer

    private let origin = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let online = Reducer.Conditions(account: .available, isOnline: true)
    private let offline = Reducer.Conditions(account: .available, isOnline: false)

    private func minute(_ offset: Double) -> Date {
        origin.addingTimeInterval(offset * 60)
    }

    private func succeeded(_ kind: Reducer.EventKind, from start: Double, to end: Double) -> Reducer.Event {
        .succeeded(kind, startedAt: minute(start), endedAt: minute(end))
    }

    private func failed(
        _ kind: Reducer.EventKind,
        at time: Double,
        disposition: Reducer.FailureDisposition? = .unknown,
        code: String? = nil
    ) -> Reducer.Event {
        .failed(kind, startedAt: minute(time - 0.5), endedAt: minute(time), disposition: disposition, code: code)
    }

    // MARK: - Only exports count

    func testImportOnlySuccessNeverYieldsBackedUp() {
        var reducer = Reducer()
        reducer.recordLocalChange(at: minute(0))
        reducer.apply(succeeded(.setup, from: 1, to: 1.1))
        reducer.apply(succeeded(.import, from: 2, to: 2.5))
        reducer.apply(succeeded(.import, from: 30, to: 31))

        XCTAssertFalse(reducer.state.everExportedSuccessfully)
        XCTAssertEqual(reducer.state.lastImportEndedAt, minute(31))
        XCTAssertEqual(reducer.backupStatus(conditions: online, now: minute(2.6)), .notBackedUp(localChangesSince: minute(0)))
        XCTAssertEqual(reducer.backupStatus(conditions: online, now: minute(32)), .notBackedUp(localChangesSince: minute(0)))
    }

    func testImportOnlyWithoutLocalChangesIsStillNotBackedUp() {
        var reducer = Reducer()
        reducer.apply(succeeded(.setup, from: 0, to: 0.1))
        reducer.apply(succeeded(.import, from: 1, to: 2))

        XCTAssertEqual(reducer.backupStatus(conditions: online, now: minute(3)), .notBackedUp(localChangesSince: nil))
    }

    func testExportSuccessYieldsBackedUp() {
        var reducer = Reducer()
        reducer.recordLocalChange(at: minute(0))
        reducer.apply(.started(.export, at: minute(1)))
        reducer.apply(succeeded(.export, from: 1, to: 1.5))

        XCTAssertTrue(reducer.state.everExportedSuccessfully)
        XCTAssertEqual(reducer.state.lastSuccessfulExportStartedAt, minute(1))
        XCTAssertEqual(reducer.state.lastSuccessfulExportEndedAt, minute(1.5))
        XCTAssertNil(reducer.state.pendingLocalChangeDate)
        XCTAssertNil(reducer.state.firstPendingLocalChangeDate)
        XCTAssertNil(reducer.exportInFlightSince)
        XCTAssertEqual(reducer.backupStatus(conditions: online, now: minute(60)), .backedUp(asOf: minute(1)))
    }

    // MARK: - Failures stick until an export succeeds

    func testExportFailureThenImportSuccessStaysFailing() {
        var reducer = Reducer()
        reducer.apply(succeeded(.export, from: 0, to: 1))
        reducer.apply(failed(.export, at: 10, disposition: .schemaRejected, code: "CKError.15"))
        reducer.apply(succeeded(.setup, from: 11, to: 11.1))
        reducer.apply(succeeded(.import, from: 12, to: 13))

        XCTAssertEqual(reducer.state.exportHealth.consecutiveFailures, 1)
        XCTAssertEqual(reducer.state.exportHealth.lastFailureCode, "CKError.15")
        XCTAssertEqual(
            reducer.backupStatus(conditions: online, now: minute(14)),
            .failing(since: minute(10), disposition: .schemaRejected)
        )
    }

    func testExportSuccessAfterFailureClearsIt() {
        var reducer = Reducer()
        reducer.apply(failed(.export, at: 5, disposition: .quotaExceeded))
        reducer.apply(failed(.export, at: 6, disposition: .quotaExceeded))
        XCTAssertEqual(reducer.state.exportHealth.consecutiveFailures, 2)

        reducer.apply(succeeded(.export, from: 7, to: 8))

        XCTAssertEqual(reducer.state.exportHealth, Reducer.ExportHealth())
        XCTAssertEqual(reducer.backupStatus(conditions: online, now: minute(9)), .backedUp(asOf: minute(7)))
    }

    func testUnclassifiedFailureStillCountsAsFailing() {
        var reducer = Reducer()
        reducer.apply(succeeded(.export, from: 0, to: 1))
        reducer.apply(failed(.export, at: 3, disposition: nil))

        XCTAssertEqual(reducer.backupStatus(conditions: online, now: minute(4)), .failing(since: minute(3), disposition: .unknown))
    }

    func testTransientFailureDoesNotHideEarlierRejection() {
        var reducer = Reducer()
        reducer.apply(failed(.export, at: 1, disposition: .schemaRejected, code: "CKError.12"))
        reducer.apply(failed(.export, at: 2, disposition: .transient, code: "CKError.3"))
        reducer.apply(failed(.export, at: 3, disposition: nil))
        reducer.apply(failed(.export, at: 4, disposition: .unknown, code: "NSCocoaErrorDomain.4097"))

        let health = reducer.state.exportHealth
        XCTAssertEqual(health.consecutiveFailures, 4)
        XCTAssertEqual(health.firstFailureAt, minute(1))
        XCTAssertEqual(health.lastFailureAt, minute(4))
        XCTAssertEqual(health.lastFailureDisposition, .schemaRejected)
        XCTAssertEqual(health.lastFailureCode, "CKError.12")
    }

    func testBenignConflictNeitherFailsNorCountsAsBackedUp() {
        var reducer = Reducer()
        reducer.apply(succeeded(.export, from: 0, to: 1))
        reducer.recordLocalChange(at: minute(2))
        reducer.apply(failed(.export, at: 3, disposition: .benign))

        XCTAssertFalse(reducer.state.exportHealth.isFailing)
        XCTAssertEqual(reducer.backupStatus(conditions: online, now: minute(10)), .notBackedUp(localChangesSince: minute(2)))
    }

    func testSetupFailureBlocksBackupUntilAnExportSucceeds() {
        var reducer = Reducer()
        reducer.apply(succeeded(.export, from: 0, to: 1))
        reducer.apply(failed(.setup, at: 60, disposition: .setupFailedWhileSignedIn, code: "NSCocoaErrorDomain.134400"))
        reducer.recordLocalChange(at: minute(70))

        XCTAssertEqual(
            reducer.backupStatus(conditions: online, now: minute(71)),
            .failing(since: minute(60), disposition: .setupFailedWhileSignedIn)
        )

        reducer.apply(succeeded(.export, from: 122, to: 123))
        XCTAssertEqual(reducer.backupStatus(conditions: online, now: minute(124)), .backedUp(asOf: minute(122)))
    }

    /// The banner tells the groomer to reopen the app; a setup that then
    /// works has disproved the failure, even before anything uploads.
    func testASetupSuccessClearsASetupFailureButNotAnUploadFailure() {
        var reducer = Reducer()
        reducer.apply(succeeded(.export, from: 0, to: 1))
        reducer.apply(failed(.setup, at: 60, disposition: .setupFailedWhileSignedIn, code: "NSCocoaErrorDomain.134400"))
        reducer.apply(succeeded(.setup, from: 120, to: 120.1))
        XCTAssertFalse(reducer.state.exportHealth.isFailing)
        XCTAssertEqual(reducer.backupStatus(conditions: online, now: minute(121)), .backedUp(asOf: minute(0)))

        reducer.apply(failed(.export, at: 130, disposition: .schemaRejected, code: "CKError.15"))
        reducer.apply(succeeded(.setup, from: 140, to: 140.1))
        XCTAssertTrue(reducer.state.exportHealth.isFailing, "Only an upload disproves a rejected upload.")
    }

    func testSignedOutSetupFailureDoesNotFollowTheGroomerIntoSignIn() {
        var reducer = Reducer()
        reducer.apply(succeeded(.export, from: 0, to: 1))
        reducer.apply(failed(.setup, at: 5, disposition: .notAuthenticated, code: "NSCocoaErrorDomain.134400"))
        reducer.apply(failed(.setup, at: 65, disposition: .notAuthenticated, code: "NSCocoaErrorDomain.134400"))

        let signedOut = Reducer.Conditions(account: .signedOut, isOnline: true)
        XCTAssertEqual(reducer.backupStatus(conditions: signedOut, now: minute(66)), .signedOut)
        XCTAssertFalse(reducer.state.exportHealth.isFailing)
        XCTAssertEqual(reducer.backupStatus(conditions: online, now: minute(67)), .backedUp(asOf: minute(0)))
    }

    func testImportFailureDoesNotAffectBackupStatus() {
        var reducer = Reducer()
        reducer.apply(succeeded(.export, from: 0, to: 1))
        reducer.apply(failed(.import, at: 2, disposition: .transient))

        XCTAssertFalse(reducer.state.exportHealth.isFailing)
        XCTAssertEqual(reducer.backupStatus(conditions: online, now: minute(3)), .backedUp(asOf: minute(0)))
    }

    func testOlderSuccessArrivingLateDoesNotClearNewerFailure() {
        var reducer = Reducer()
        reducer.apply(failed(.export, at: 10, disposition: .limitExceeded))
        reducer.apply(succeeded(.export, from: 4, to: 5))

        XCTAssertTrue(reducer.state.exportHealth.isFailing)
        XCTAssertEqual(reducer.backupStatus(conditions: online, now: minute(11)), .failing(since: minute(10), disposition: .limitExceeded))
    }

    func testOlderFailureArrivingLateIsIgnored() {
        var reducer = Reducer()
        reducer.apply(succeeded(.export, from: 9, to: 10))
        reducer.apply(failed(.export, at: 5, disposition: .transient))

        XCTAssertFalse(reducer.state.exportHealth.isFailing)
    }

    // MARK: - Pending local changes and the grace period

    func testPendingChangeAfterLastExportIsNotBackedUpAfterGrace() {
        var reducer = Reducer()
        reducer.apply(succeeded(.export, from: 0, to: 1))
        reducer.recordLocalChange(at: minute(10))

        XCTAssertEqual(reducer.backupStatus(conditions: online, now: minute(14)), .backedUp(asOf: minute(0)))
        XCTAssertEqual(reducer.backupStatus(conditions: online, now: minute(16)), .notBackedUp(localChangesSince: minute(10)))
    }

    func testGraceRunsFromOldestUncoveredChange() {
        var reducer = Reducer()
        reducer.apply(succeeded(.export, from: 0, to: 1))
        reducer.recordLocalChange(at: minute(10))
        reducer.recordLocalChange(at: minute(13))
        reducer.recordLocalChange(at: minute(15.5))

        // The newest change is 30 s old, but the first has waited 6 minutes.
        XCTAssertEqual(reducer.backupStatus(conditions: online, now: minute(16)), .notBackedUp(localChangesSince: minute(10)))
    }

    func testNoGraceWhileOfflineOrAccountUnavailable() {
        var reducer = Reducer()
        reducer.apply(succeeded(.export, from: 0, to: 1))
        reducer.recordLocalChange(at: minute(10))

        XCTAssertEqual(reducer.backupStatus(conditions: offline, now: minute(10.5)), .notBackedUp(localChangesSince: minute(10)))
        let unavailable = Reducer.Conditions(account: .temporarilyUnavailable, isOnline: true)
        XCTAssertEqual(reducer.backupStatus(conditions: unavailable, now: minute(10.5)), .notBackedUp(localChangesSince: minute(10)))
    }

    func testChangeSavedDuringExportStaysPending() {
        var reducer = Reducer()
        reducer.recordLocalChange(at: minute(0))
        reducer.apply(.started(.export, at: minute(1)))
        reducer.recordLocalChange(at: minute(1.5))
        reducer.apply(succeeded(.export, from: 1, to: 2))

        XCTAssertEqual(reducer.state.pendingLocalChangeDate, minute(1.5))
        XCTAssertEqual(reducer.oldestUncoveredLocalChange, minute(1))
        XCTAssertEqual(reducer.backupStatus(conditions: online, now: minute(10)), .notBackedUp(localChangesSince: minute(1)))

        reducer.apply(succeeded(.export, from: 11, to: 12))
        XCTAssertNil(reducer.oldestUncoveredLocalChange)
        XCTAssertEqual(reducer.backupStatus(conditions: online, now: minute(13)), .backedUp(asOf: minute(11)))
    }

    func testChangeAlreadyCoveredByAnExportIsNotPending() {
        var reducer = Reducer()
        reducer.apply(succeeded(.export, from: 5, to: 6))
        reducer.recordLocalChange(at: minute(4))

        XCTAssertNil(reducer.state.pendingLocalChangeDate)
        XCTAssertEqual(reducer.backupStatus(conditions: offline, now: minute(30)), .backedUp(asOf: minute(5)))
    }

    // MARK: - Uploading

    func testExportInFlightShowsUploadingOnlyWhenItCarriesSomethingNew() {
        var reducer = Reducer()
        reducer.apply(.started(.export, at: minute(0)))
        XCTAssertEqual(reducer.backupStatus(conditions: online, now: minute(0.1)), .uploading)
        reducer.apply(succeeded(.export, from: 0, to: 1))

        // Nothing uncovered: a routine background export keeps the checkmark.
        reducer.apply(.started(.export, at: minute(5)))
        XCTAssertEqual(reducer.backupStatus(conditions: online, now: minute(5.1)), .backedUp(asOf: minute(0)))
        reducer.apply(succeeded(.export, from: 5, to: 6))

        reducer.recordLocalChange(at: minute(7))
        reducer.apply(.started(.export, at: minute(7.1)))
        XCTAssertEqual(reducer.backupStatus(conditions: online, now: minute(7.2)), .uploading)
    }

    func testFailureOutranksAnExportInFlight() {
        var reducer = Reducer()
        reducer.apply(failed(.export, at: 1, disposition: .transient))
        reducer.apply(.started(.export, at: minute(2)))

        XCTAssertEqual(reducer.backupStatus(conditions: online, now: minute(2.1)), .failing(since: minute(1), disposition: .transient))
    }

    // MARK: - Conditions

    func testLocalOnlyModeOverridesEverything() {
        var reducer = Reducer()
        reducer.apply(succeeded(.export, from: 0, to: 1))
        reducer.apply(failed(.export, at: 2))
        let localOnly = Reducer.Conditions(account: .available, isOnline: true, isLocalOnly: true)

        XCTAssertEqual(reducer.backupStatus(conditions: localOnly, now: minute(3)), .localOnly)
    }

    func testSignedOut() {
        var reducer = Reducer()
        reducer.apply(succeeded(.export, from: 0, to: 1))
        let signedOut = Reducer.Conditions(account: .signedOut, isOnline: true)

        XCTAssertEqual(reducer.backupStatus(conditions: signedOut, now: minute(2)), .signedOut)
        reducer.apply(failed(.export, at: 3, disposition: .notAuthenticated))
        XCTAssertEqual(reducer.backupStatus(conditions: signedOut, now: minute(4)), .signedOut)
    }

    func testUnknownAccountIsUnknownUnlessAFailureIsOnRecord() {
        var reducer = Reducer()
        reducer.apply(succeeded(.export, from: 0, to: 1))
        let checking = Reducer.Conditions(account: .unknown, isOnline: true)

        XCTAssertEqual(reducer.backupStatus(conditions: checking, now: minute(2)), .unknown)
        reducer.apply(failed(.export, at: 3, disposition: .schemaRejected))
        XCTAssertEqual(reducer.backupStatus(conditions: checking, now: minute(4)), .failing(since: minute(3), disposition: .schemaRejected))
    }

    // MARK: - Persistence

    func testStateRoundTripsThroughCodable() throws {
        var reducer = Reducer()
        reducer.apply(succeeded(.export, from: 0, to: 1))
        reducer.apply(succeeded(.import, from: 2, to: 3))
        reducer.apply(failed(.export, at: 4, disposition: .limitExceeded, code: "CKError.27"))
        reducer.recordLocalChange(at: minute(5))

        let data = try JSONEncoder().encode(reducer.state)
        let decoded = try JSONDecoder().decode(Reducer.State.self, from: data)

        XCTAssertEqual(decoded, reducer.state)
        XCTAssertEqual(Reducer(state: decoded).backupStatus(conditions: online, now: minute(6)), .failing(since: minute(4), disposition: .limitExceeded))
    }

    func testDecodingToleratesMissingKeysAndUnknownDispositions() throws {
        let empty = try JSONDecoder().decode(Reducer.State.self, from: Data("{}".utf8))
        XCTAssertEqual(empty, Reducer.State())

        let fromLaterBuild = Data("""
        {
          "lastSuccessfulExportStartedAt": 800000000,
          "exportHealth": {
            "consecutiveFailures": 2,
            "firstFailureAt": 800000600,
            "lastFailureDisposition": "somethingAddedLater"
          }
        }
        """.utf8)
        let decoded = try JSONDecoder().decode(Reducer.State.self, from: fromLaterBuild)

        XCTAssertTrue(decoded.everExportedSuccessfully, "An export start on record implies a successful export.")
        XCTAssertEqual(decoded.exportHealth.consecutiveFailures, 2)
        XCTAssertEqual(decoded.exportHealth.lastFailureDisposition, .unknown)
        XCTAssertEqual(
            Reducer(state: decoded).backupStatus(conditions: online, now: minute(20)),
            .failing(since: minute(10), disposition: .unknown)
        )
    }

    /// The monitor converts a classification with
    /// `FailureDisposition(rawValue: disposition.diagnosticName)`. A renamed
    /// category would silently become `.unknown`, so pin every one.
    func testEveryClassifierDispositionHasAMatchingCase() {
        let classified: [SyncErrorClassifier.Disposition] = [
            .transient,
            .userActionable(.quotaExceeded),
            .userActionable(.notAuthenticated),
            .userActionable(.accountTemporarilyUnavailable),
            .userActionable(.userDeletedZone),
            .schemaRejected,
            .limitExceeded,
            .benign,
            .setupFailedWhileSignedIn,
            .unknown
        ]
        let mapped = classified.map { Reducer.FailureDisposition(rawValue: $0.diagnosticName) }

        XCTAssertFalse(mapped.contains(nil), "Unmapped: \(zip(classified, mapped).filter { $1 == nil }.map { $0.0.diagnosticName })")
        XCTAssertEqual(Set(mapped.compactMap { $0 }), Set(Reducer.FailureDisposition.allCases))
    }
}
