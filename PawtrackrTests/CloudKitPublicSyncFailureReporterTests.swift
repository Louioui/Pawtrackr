import XCTest
import CloudKit
@testable import Pawtrackr

/// The public-database reporter: what a report may carry, when it may go out,
/// and how often. The sender is injected, so nothing here reaches CloudKit.
@MainActor
final class CloudKitPublicSyncFailureReporterTests: XCTestCase {
    private typealias Reporter = CloudKitPublicSyncFailureReporter

    private var defaults: UserDefaults!
    private var suiteName: String!
    private var now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private var enabled = true

    override func setUp() async throws {
        suiteName = "CloudKitPublicSyncFailureReporterTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        enabled = true
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    private func makeReporter(
        send: @escaping Reporter.Send = { _ in XCTFail("Nothing should be sent") }
    ) -> Reporter {
        Reporter(
            defaults: defaults,
            now: { [unowned self] in self.now },
            appVersion: "1.0.3",
            buildNumber: "4",
            osVersion: "26.5.0",
            platform: "iPadOS",
            isEnabled: { [unowned self] in self.enabled },
            send: send
        )
    }

    /// Records every report the reporter would have saved.
    private func makeRecordingReporter(_ sent: SentReports) -> Reporter {
        makeReporter(send: { report in await sent.append(report) })
    }

    private func classification(
        _ disposition: SyncErrorClassifier.Disposition,
        code: Int = 12
    ) -> SyncErrorClassifier.Classification {
        SyncErrorClassifier.Classification(
            disposition: disposition,
            innermostDomain: CKError.errorDomain,
            innermostCode: code,
            serverMessage: "Cannot create new type CD_LoyaltyConfig in production schema"
        )
    }

    // MARK: - Payload

    func testRecordHoldsOnlyTheSevenReportFields() {
        let report = PublicSyncFailureReport(
            classification: classification(.schemaRejected),
            appVersion: "1.0.3",
            buildNumber: "4",
            osVersion: "26.5.0",
            platform: "iPadOS"
        )
        let record = report.makeRecord()

        XCTAssertEqual(record.recordType, "PTSyncFailureReport")
        XCTAssertEqual(Set(record.allKeys()), PublicSyncFailureReport.Field.all)
        XCTAssertEqual(PublicSyncFailureReport.Field.all.count, 7)
        XCTAssertEqual(record["disposition"] as? String, "schemaRejected")
        XCTAssertEqual(record["errorDomain"] as? String, CKError.errorDomain)
        XCTAssertEqual(record["errorCode"] as? Int64, 12)
        XCTAssertEqual(record["appVersion"] as? String, "1.0.3")
        XCTAssertEqual(record["buildNumber"] as? String, "4")
        XCTAssertEqual(record["osVersion"] as? String, "26.5.0")
        XCTAssertEqual(record["platform"] as? String, "iPadOS")

        // CloudKit's own wording names record types; it never leaves the device.
        for key in record.allKeys() {
            XCTAssertFalse(String(describing: record[key] as Any).contains("CD_LoyaltyConfig"), key)
        }
    }

    func testSentReportMatchesTheClassification() async throws {
        let sent = SentReports()
        let reporter = makeRecordingReporter(sent)

        XCTAssertTrue(reporter.reportIfNeeded(classification(.limitExceeded, code: 27)))
        let reports = await sent.waitForCount(1)

        XCTAssertEqual(reports, [
            PublicSyncFailureReport(
                disposition: "limitExceeded",
                errorDomain: CKError.errorDomain,
                errorCode: 27,
                appVersion: "1.0.3",
                buildNumber: "4",
                osVersion: "26.5.0",
                platform: "iPadOS"
            )
        ])
    }

    func testPlatformAndVersionsAreDescribedWithoutTheDevice() {
        #if os(macOS)
        XCTAssertEqual(Reporter.currentPlatform, "macOS")
        #else
        XCTAssertTrue(["iOS", "iPadOS"].contains(Reporter.currentPlatform), Reporter.currentPlatform)
        #endif
        XCTAssertNotNil(Reporter.currentOSVersion.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression), Reporter.currentOSVersion)
        XCTAssertFalse(Reporter.currentBuildNumber.isEmpty)
    }

    // MARK: - Which failures

    func testPermanentFailuresAreReportable() {
        XCTAssertTrue(Reporter.isReportable(.schemaRejected))
        XCTAssertTrue(Reporter.isReportable(.limitExceeded))
        XCTAssertTrue(Reporter.isReportable(.setupFailedWhileSignedIn))
    }

    func testRetryableAndAccountFailuresAreNotReported() {
        let reporter = makeReporter()
        let ignored: [SyncErrorClassifier.Disposition] = [
            .transient, .benign, .unknown,
            .userActionable(.quotaExceeded), .userActionable(.notAuthenticated),
            .userActionable(.accountTemporarilyUnavailable), .userActionable(.userDeletedZone)
        ]
        for disposition in ignored {
            XCTAssertFalse(Reporter.isReportable(disposition), "\(disposition)")
            XCTAssertFalse(reporter.reportIfNeeded(classification(disposition)), "\(disposition)")
        }
    }

    // MARK: - How often

    func testEachDispositionIsReportedOncePerDay() async {
        let sent = SentReports()
        let reporter = makeRecordingReporter(sent)

        XCTAssertTrue(reporter.reportIfNeeded(classification(.schemaRejected)))
        XCTAssertFalse(reporter.reportIfNeeded(classification(.schemaRejected)))
        // Each rejection has its own allowance.
        XCTAssertTrue(reporter.reportIfNeeded(classification(.limitExceeded, code: 27)))
        XCTAssertTrue(reporter.reportIfNeeded(classification(.setupFailedWhileSignedIn, code: 134_400)))
        XCTAssertFalse(reporter.reportIfNeeded(classification(.setupFailedWhileSignedIn, code: 134_400)))

        now = now.addingTimeInterval(23 * 60 * 60)
        XCTAssertFalse(makeRecordingReporter(sent).reportIfNeeded(classification(.schemaRejected)), "The limit survives a relaunch")

        now = now.addingTimeInterval(60 * 60)
        XCTAssertTrue(makeRecordingReporter(sent).reportIfNeeded(classification(.schemaRejected)))

        let reports = await sent.waitForCount(4)
        XCTAssertEqual(reports.map(\.disposition).sorted(), [
            "limitExceeded", "schemaRejected", "schemaRejected", "setupFailedWhileSignedIn"
        ])
    }

    func testTelemetryAllowanceDoesNotUseUpThePublicOne() async {
        let sent = SentReports()
        var logged: [String] = []
        let composite = CompositeSyncFailureReporter([
            TelemetrySyncFailureReporter(
                defaults: defaults,
                now: { [unowned self] in self.now },
                appVersion: "1.0.3-4",
                osVersion: "iOS 26.5.0",
                send: { event, _ in logged.append(event) }
            ),
            makeRecordingReporter(sent)
        ])

        XCTAssertTrue(composite.reportIfNeeded(classification(.schemaRejected)))
        XCTAssertFalse(composite.reportIfNeeded(classification(.schemaRejected)))

        let reports = await sent.waitForCount(1)
        XCTAssertEqual(logged, [TelemetrySyncFailureReporter.eventName])
        XCTAssertEqual(reports.map(\.disposition), ["schemaRejected"])
    }

    func testCompositeReportsWhenOnlyThePublicReporterTakesIt() async {
        let sent = SentReports()
        var logged: [String] = []
        let composite = CompositeSyncFailureReporter([
            TelemetrySyncFailureReporter(
                defaults: defaults,
                now: { [unowned self] in self.now },
                send: { event, _ in logged.append(event) }
            ),
            makeRecordingReporter(sent)
        ])

        // Telemetry ignores setup failures; the public reporter doesn't.
        XCTAssertTrue(composite.reportIfNeeded(classification(.setupFailedWhileSignedIn, code: 134_400)))

        let reports = await sent.waitForCount(1)
        XCTAssertTrue(logged.isEmpty)
        XCTAssertEqual(reports.map(\.disposition), ["setupFailedWhileSignedIn"])
    }

    func testClockSetBackwardsDoesNotSilenceReports() async {
        let sent = SentReports()
        let reporter = makeRecordingReporter(sent)
        XCTAssertTrue(reporter.reportIfNeeded(classification(.schemaRejected)))
        now = now.addingTimeInterval(-3 * 24 * 60 * 60)
        XCTAssertTrue(reporter.reportIfNeeded(classification(.schemaRejected)))
        _ = await sent.waitForCount(2)
    }

    func testFailedSaveIsSwallowedAndStillUsesTheAllowance() async {
        let attempted = expectation(description: "save attempted")
        let reporter = makeReporter(send: { _ in
            attempted.fulfill()
            throw CKError(.notAuthenticated)
        })

        XCTAssertTrue(reporter.reportIfNeeded(classification(.schemaRejected)))
        await fulfillment(of: [attempted], timeout: 5)

        // Retrying a save that just failed on every export would hammer CloudKit.
        XCTAssertFalse(reporter.reportIfNeeded(classification(.schemaRejected)))
    }

    // MARK: - When

    func testDisabledReporterSendsNothingAndKeepsTheAllowance() async {
        enabled = false
        let sent = SentReports()
        let reporter = makeRecordingReporter(sent)
        XCTAssertFalse(reporter.reportIfNeeded(classification(.schemaRejected)))

        // A launch that couldn't send mustn't cost the next one its report.
        enabled = true
        XCTAssertTrue(reporter.reportIfNeeded(classification(.schemaRejected)))
        let reports = await sent.waitForCount(1)
        XCTAssertEqual(reports.count, 1)
    }

    func testReleaseBuildsReportWhileMirroring() {
        XCTAssertTrue(Reporter.isEnabled(isMirroring: true, isTestRun: false, isDebugBuild: false, arguments: []))
    }

    func testLocalOnlyAndDisabledModesNeverReport() {
        XCTAssertFalse(Reporter.isEnabled(isMirroring: false, isTestRun: false, isDebugBuild: false, arguments: []))
        XCTAssertFalse(Reporter.isEnabled(isMirroring: false, isTestRun: false, isDebugBuild: true, arguments: [Reporter.launchArgument]))
    }

    func testTestRunsNeverReportEvenWhenAsked() {
        XCTAssertFalse(Reporter.isEnabled(isMirroring: true, isTestRun: true, isDebugBuild: false, arguments: []))
        XCTAssertFalse(Reporter.isEnabled(isMirroring: true, isTestRun: true, isDebugBuild: true, arguments: [Reporter.launchArgument]))
        // This process is a test run, so the defaults must say no too.
        XCTAssertFalse(Reporter.isEnabled(isMirroring: true, arguments: [Reporter.launchArgument]))
    }

    func testDebugBuildsReportOnlyWithTheLaunchArgument() {
        XCTAssertFalse(Reporter.isEnabled(isMirroring: true, isTestRun: false, isDebugBuild: true, arguments: []))
        XCTAssertTrue(Reporter.isEnabled(isMirroring: true, isTestRun: false, isDebugBuild: true, arguments: ["-foo", "-PawtrackrSendSyncFailureReports"]))
    }
}

/// Collects reports from the reporter's detached send task.
private actor SentReports {
    private var reports: [PublicSyncFailureReport] = []

    func append(_ report: PublicSyncFailureReport) {
        reports.append(report)
    }

    /// The sends run detached, so wait for them rather than assume ordering.
    func waitForCount(_ count: Int, timeout: TimeInterval = 5) async -> [PublicSyncFailureReport] {
        let deadline = Date().addingTimeInterval(timeout)
        while reports.count < count, Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(reports.count, count, "Expected \(count) report(s)")
        return reports
    }
}
