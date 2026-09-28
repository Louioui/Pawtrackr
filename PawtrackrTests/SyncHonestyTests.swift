import XCTest
@testable import Pawtrackr

/// What the iCloud screens may say. Every status label comes from the
/// backup status; the circuit breaker only backs off the manual check and
/// always comes back on its own; other devices' heartbeats and presence are
/// "recent", never "live" or "online".
final class SyncHonestyTests: XCTestCase {
    private let origin = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func seconds(_ offset: TimeInterval) -> Date {
        origin.addingTimeInterval(offset)
    }

    // MARK: - Circuit breaker

    func testFailureOpensWithABoundedDelayThatGrowsAndCaps() {
        var breaker = SyncCircuitBreaker()
        breaker.recordFailure(now: origin)
        XCTAssertEqual(breaker.state, .open(until: seconds(30), failures: 1))

        breaker.recordFailure(now: origin)
        XCTAssertEqual(breaker.manualCheckAvailableAt(now: origin), seconds(60))

        for _ in 0..<20 {
            breaker.recordFailure(now: origin)
        }
        XCTAssertEqual(
            breaker.manualCheckAvailableAt(now: origin),
            seconds(breaker.configuration.maximumDelay),
            "A string of failures still lets the groomer check again within the cap."
        )
        XCTAssertLessThanOrEqual(breaker.configuration.maximumDelay, 5 * 60)
    }

    func testConstrainedNetworkDoublesTheDelayButStaysUnderTheCap() {
        var breaker = SyncCircuitBreaker()
        breaker.recordFailure(now: origin, constrained: true)
        XCTAssertEqual(breaker.manualCheckAvailableAt(now: origin), seconds(60))

        for _ in 0..<20 {
            breaker.recordFailure(now: origin, constrained: true)
        }
        XCTAssertEqual(breaker.manualCheckAvailableAt(now: origin), seconds(breaker.configuration.maximumDelay))
    }

    func testNetworkDropNeitherOpensTheBreakerNorGrowsTheBackoff() {
        let offline = NetworkCondition(status: .offline, isExpensive: false, isConstrained: false)

        var closed = SyncCircuitBreaker()
        closed.observeNetwork(offline, now: origin)
        XCTAssertEqual(closed.state, .closed)
        XCTAssertEqual(closed.consecutiveFailures, 0)

        var open = SyncCircuitBreaker()
        open.recordFailure(now: origin)
        let before = open.state
        open.observeNetwork(offline, now: seconds(5))
        XCTAssertEqual(open.state, before)
        XCTAssertEqual(open.consecutiveFailures, 1)
    }

    func testNetworkRestoreLetsACheckThroughStraightAway() {
        var breaker = SyncCircuitBreaker()
        breaker.recordFailure(now: origin)
        XCTAssertNotNil(breaker.manualCheckAvailableAt(now: seconds(1)))

        breaker.observeNetwork(NetworkCondition(status: .online, isExpensive: false, isConstrained: false), now: seconds(1))
        XCTAssertEqual(breaker.state, .halfOpen(probeStartedAt: seconds(1), failures: 1))
        XCTAssertNil(breaker.manualCheckAvailableAt(now: seconds(1)))
        XCTAssertTrue(breaker.beginProbeIfAllowed(now: seconds(1)))
    }

    func testSuccessClosesAndResetsTheBackoff() {
        var breaker = SyncCircuitBreaker()
        breaker.recordFailure(now: origin)
        breaker.recordFailure(now: origin)
        breaker.recordSuccess()
        XCTAssertEqual(breaker.state, .closed)
        XCTAssertEqual(breaker.consecutiveFailures, 0)

        breaker.recordFailure(now: origin)
        XCTAssertEqual(breaker.manualCheckAvailableAt(now: origin), seconds(30), "Backoff starts over after a success.")
    }

    func testProbeWaitsForTheDeadlineThenHalfOpens() {
        var breaker = SyncCircuitBreaker()
        breaker.recordFailure(now: origin)

        XCTAssertFalse(breaker.beginProbeIfAllowed(now: seconds(29)))
        XCTAssertTrue(breaker.state.isOpen)

        XCTAssertNil(breaker.manualCheckAvailableAt(now: seconds(30)), "A deadline that has passed is no pause.")
        XCTAssertTrue(breaker.beginProbeIfAllowed(now: seconds(30)))
        XCTAssertEqual(breaker.state, .halfOpen(probeStartedAt: seconds(30), failures: 1))
    }

    // MARK: - Manual check availability

    func testManualCheckIsNeverACountdownOfZero() {
        XCTAssertEqual(ManualCheckAvailability.resolve(cooldownSeconds: 0, pausedUntil: nil, now: origin), .available)
        XCTAssertEqual(
            ManualCheckAvailability.resolve(cooldownSeconds: 0, pausedUntil: seconds(-1), now: origin),
            .available,
            "An expired pause re-enables the button instead of reading 'Check again in 0s'."
        )
        XCTAssertEqual(ManualCheckAvailability.resolve(cooldownSeconds: 0, pausedUntil: origin, now: origin), .available)

        for cooldown in -3...0 {
            if case .coolingDown = ManualCheckAvailability.resolve(cooldownSeconds: cooldown, pausedUntil: nil, now: origin) {
                XCTFail("A cooldown of \(cooldown)s must not be shown.")
            }
        }
    }

    func testCooldownThenPauseAfterError() {
        XCTAssertEqual(
            ManualCheckAvailability.resolve(cooldownSeconds: 12, pausedUntil: seconds(90), now: origin),
            .coolingDown(seconds: 12)
        )
        XCTAssertEqual(
            ManualCheckAvailability.resolve(cooldownSeconds: 0, pausedUntil: seconds(90), now: origin),
            .pausedAfterError(until: seconds(90))
        )
        XCTAssertFalse(ManualCheckAvailability.pausedAfterError(until: seconds(90)).isAvailable)
    }

    func testManualCheckTitlesSayWhatIsHappening() {
        XCTAssertTrue(ManualCheckAvailability.coolingDown(seconds: 12).buttonTitle.contains("12"))

        let paused = ManualCheckAvailability.pausedAfterError(until: seconds(90)).buttonTitle
        XCTAssertTrue(
            paused.contains(seconds(90).formatted(date: .omitted, time: .shortened)),
            "The pause names the time the check comes back: \(paused)"
        )
        XCTAssertFalse(paused.lowercased().contains("battery"))
        XCTAssertFalse(paused.lowercased().contains("offline-first"))
    }

    // MARK: - Status labels

    func testStatusLabelComesFromTheBackupStatus() {
        XCTAssertEqual(BackupStatusLabel(.backedUp(asOf: origin)), .backedUp)
        XCTAssertEqual(BackupStatusLabel(.uploading), .uploading)
        XCTAssertEqual(BackupStatusLabel(.notBackedUp(localChangesSince: nil)), .notBackedUp)
        XCTAssertEqual(BackupStatusLabel(.notBackedUp(localChangesSince: origin)), .notBackedUp)
        XCTAssertEqual(BackupStatusLabel(.failing(since: origin, disposition: .transient)), .needsAttention)
        XCTAssertEqual(BackupStatusLabel(.failing(since: origin, disposition: .quotaExceeded)), .needsAttention)
        XCTAssertEqual(BackupStatusLabel(.signedOut), .iCloudOff)
        XCTAssertEqual(BackupStatusLabel(.localOnly), .iCloudOff)
        XCTAssertEqual(BackupStatusLabel(.unknown), .checkingAccount)
    }

    func testOnlyABackupReadsAsSuccess() {
        let reassuring = ["ready", "healthy", "synced", "online"]
        let labels: [BackupStatusLabel] = [.uploading, .notBackedUp, .needsAttention, .iCloudOff, .checkingAccount]
        for label in labels {
            let title = label.title.lowercased()
            XCTAssertFalse(title.isEmpty)
            for word in reassuring {
                XCTAssertFalse(title.contains(word), "\(label) reads '\(label.title)'")
            }
            XCTAssertNotEqual(label.title, BackupStatusLabel.backedUp.title)
        }
    }

    func testPendingCountIsOnlyGreenWhenEverythingIsBackedUp() {
        let backedUp = BackupStatus.backedUp(asOf: origin)
        XCTAssertEqual(SyncStatusPolicy.pendingTint(waitingCount: 0, isMirroring: true, status: backedUp), .success)
        XCTAssertEqual(SyncStatusPolicy.pendingTint(waitingCount: 2, isMirroring: true, status: backedUp), .warning)

        // An empty queue proves nothing when iCloud is off or nothing is confirmed.
        XCTAssertEqual(SyncStatusPolicy.pendingTint(waitingCount: 0, isMirroring: false, status: .localOnly), .neutral)
        XCTAssertEqual(SyncStatusPolicy.pendingTint(waitingCount: 3, isMirroring: false, status: .localOnly), .warning)
        XCTAssertEqual(SyncStatusPolicy.pendingTint(waitingCount: 0, isMirroring: true, status: .notBackedUp(localChangesSince: nil)), .neutral)
        XCTAssertEqual(SyncStatusPolicy.pendingTint(waitingCount: 0, isMirroring: true, status: .signedOut), .neutral)
        XCTAssertEqual(SyncStatusPolicy.pendingTint(waitingCount: 0, isMirroring: true, status: .unknown), .neutral)
        XCTAssertEqual(
            SyncStatusPolicy.pendingTint(waitingCount: 0, isMirroring: true, status: .failing(since: origin, disposition: .transient)),
            .neutral
        )
    }

    // MARK: - Devices and presence

    func testHeartbeatAgeBuckets() {
        typealias Age = DeviceActivityPolicy.HeartbeatAge
        XCTAssertEqual(Age(lastSeen: origin, now: origin), .recent)
        XCTAssertEqual(Age(lastSeen: seconds(30), now: origin), .recent, "A clock slightly ahead still reads as recent.")
        XCTAssertEqual(Age(lastSeen: seconds(-(10 * 60) + 1), now: origin), .recent)
        XCTAssertEqual(Age(lastSeen: seconds(-(10 * 60)), now: origin), .lastDay)
        XCTAssertEqual(Age(lastSeen: seconds(-(24 * 60 * 60) + 1), now: origin), .lastDay)
        XCTAssertEqual(Age(lastSeen: seconds(-(24 * 60 * 60)), now: origin), .stale)
    }

    func testHeartbeatWordingNeverClaimsLiveOrOnline() {
        let ages: [DeviceActivityPolicy.HeartbeatAge] = [.recent, .lastDay, .stale]
        for age in ages {
            let title = age.title.lowercased()
            XCTAssertFalse(title.contains("online"), age.title)
            XCTAssertFalse(title.contains("live"), age.title)
            XCTAssertFalse(title.contains("active now"), age.title)
        }
    }

    func testRecentlyOpenElsewhereExcludesThisDeviceAndStaleRecords() {
        let me = UUID()
        let frontDesk = UUID()
        let backRoom = UUID()
        let oldMac = UUID()

        func record(_ device: UUID, _ name: String, ageSeconds: TimeInterval, type: String? = "client") -> PresenceRecord {
            let record = PresenceRecord(deviceID: device, deviceName: name)
            record.recordType = type
            record.updatedAt = seconds(-ageSeconds)
            return record
        }

        let records = [
            record(me, "This iPad", ageSeconds: 5),
            record(frontDesk, "Front Desk", ageSeconds: 240),
            record(frontDesk, "Front Desk", ageSeconds: 60, type: "pet"),
            record(backRoom, "Back Room", ageSeconds: 30),
            record(oldMac, "Old Mac", ageSeconds: 11 * 60)
        ]

        let shown = DeviceActivityPolicy.recentlyOpenElsewhere(records, currentDeviceID: me, now: origin)
        XCTAssertEqual(shown.map(\.deviceID), [backRoom, frontDesk], "Newest first, one per device, no self, no stale.")
        XCTAssertEqual(shown.last?.recordType, "pet", "Each device keeps its newest record.")
    }

    func testPresenceSummaryTranslatesTheRecordType() {
        let client = DeviceActivityPolicy.presenceSummary(deviceName: "Front Desk", recordType: " Client ")
        let pet = DeviceActivityPolicy.presenceSummary(deviceName: "Front Desk", recordType: "pet")
        let other = DeviceActivityPolicy.presenceSummary(deviceName: "Front Desk", recordType: "invoice")
        let none = DeviceActivityPolicy.presenceSummary(deviceName: "Front Desk", recordType: nil)
        let unnamed = DeviceActivityPolicy.presenceSummary(deviceName: "   ", recordType: "pet")

        XCTAssertEqual(client, "Front Desk had a client open")
        XCTAssertEqual(pet, "Front Desk had a pet open")
        XCTAssertEqual(other, "Front Desk had Pawtrackr open")
        XCTAssertEqual(none, other)
        XCTAssertFalse(unnamed.hasPrefix(" "))
        XCTAssertTrue(unnamed.hasSuffix("had a pet open"))
        for summary in [client, pet, other] {
            XCTAssertFalse(summary.lowercased().contains("active now"))
            XCTAssertFalse(summary.lowercased().contains("viewing"))
        }
    }
}
