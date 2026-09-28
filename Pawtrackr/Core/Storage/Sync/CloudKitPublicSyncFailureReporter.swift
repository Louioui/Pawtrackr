//
//  CloudKitPublicSyncFailureReporter.swift
//  Pawtrackr
//
//  Sends each permanent iCloud failure to the developer as one record in the
//  app's CloudKit public database. Pawtrackr has no server, and this is the
//  only channel the developer can read without one.
//
//  The record holds the seven fields of PublicSyncFailureReport and nothing
//  else. CloudKit adds its own metadata, including the creator's user record
//  ID; docs/cloudkit/sync-failure-reports.md covers what that means for App
//  Privacy, and how to set up the record type in CloudKit Console.
//

import CloudKit
import Foundation
import OSLog
#if canImport(UIKit)
import UIKit
#endif

/// Everything a public failure report carries. Adding a field changes what
/// Pawtrackr collects: update docs/cloudkit/sync-failure-reports.md and the
/// App Privacy answers with it.
struct PublicSyncFailureReport: Equatable, Sendable {
    static let recordType = "PTSyncFailureReport"

    enum Field {
        static let disposition = "disposition"
        static let errorDomain = "errorDomain"
        static let errorCode = "errorCode"
        static let appVersion = "appVersion"
        static let buildNumber = "buildNumber"
        static let osVersion = "osVersion"
        static let platform = "platform"

        static let all: Set<String> = [disposition, errorDomain, errorCode, appVersion, buildNumber, osVersion, platform]
    }

    let disposition: String
    let errorDomain: String
    let errorCode: Int64
    let appVersion: String
    let buildNumber: String
    /// Numbers only ("26.5.0"); `platform` says which OS.
    let osVersion: String
    /// "iOS", "iPadOS" or "macOS".
    let platform: String

    /// Built where it's saved: CKRecord isn't Sendable, the report is.
    func makeRecord() -> CKRecord {
        let record = CKRecord(recordType: Self.recordType)
        record[Field.disposition] = disposition
        record[Field.errorDomain] = errorDomain
        // Int64, so Development's on-demand schema types the field INT(64).
        record[Field.errorCode] = errorCode
        record[Field.appVersion] = appVersion
        record[Field.buildNumber] = buildNumber
        record[Field.osVersion] = osVersion
        record[Field.platform] = platform
        return record
    }
}

extension PublicSyncFailureReport {
    /// The server message stays behind: it can name record types and IDs.
    init(
        classification: SyncErrorClassifier.Classification,
        appVersion: String,
        buildNumber: String,
        osVersion: String,
        platform: String
    ) {
        self.init(
            disposition: classification.disposition.diagnosticName,
            errorDomain: classification.innermostDomain,
            errorCode: Int64(classification.innermostCode),
            appVersion: appVersion,
            buildNumber: buildNumber,
            osVersion: osVersion,
            platform: platform
        )
    }
}

@MainActor
final class CloudKitPublicSyncFailureReporter: SyncFailureReporting {
    typealias Send = @Sendable (PublicSyncFailureReport) async throws -> Void

    /// Required for a DEBUG build to send anything. Release builds send
    /// without it; tests never send.
    nonisolated static let launchArgument = "-PawtrackrSendSyncFailureReports"
    /// Only ever in Development: DEBUG builds don't talk to Production.
    nonisolated static let developmentSampleDisposition = "developmentSample"

    nonisolated static let containerIdentifier = "iCloud.PartnerShipWithMedia.Pawtrackr"
    // Separate from the telemetry reporter's keys: the composite runs that one
    // first, and a shared allowance would never reach this one.
    private static let lastSentKeyPrefix = "cloudkit.failureReport.publicLastSent."
    nonisolated private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "CloudKit")

    nonisolated static var isDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    private let throttle: SyncFailureReportThrottle
    private let isEnabled: @MainActor () -> Bool
    private let appVersion: String
    private let buildNumber: String
    private let osVersion: String
    private let platform: String
    private let send: Send

    /// `isEnabled` is asked on every report, not once: the monitor learns its
    /// mode after this reporter exists.
    init(
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        appVersion: String = CloudKitPublicSyncFailureReporter.currentAppVersion,
        buildNumber: String = CloudKitPublicSyncFailureReporter.currentBuildNumber,
        osVersion: String = CloudKitPublicSyncFailureReporter.currentOSVersion,
        // Nil means this device. UIDevice is main-actor only, and default
        // arguments aren't evaluated on the main actor.
        platform: String? = nil,
        isEnabled: @escaping @MainActor () -> Bool,
        send: @escaping Send = { try await CloudKitPublicSyncFailureReporter.saveToPublicDatabase($0) }
    ) {
        self.throttle = SyncFailureReportThrottle(keyPrefix: Self.lastSentKeyPrefix, defaults: defaults, now: now)
        self.isEnabled = isEnabled
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.osVersion = osVersion
        self.platform = platform ?? Self.currentPlatform
        self.send = send
    }

    /// Failures retrying won't fix: a Production schema missing a type or
    /// field, a record over CloudKit's limits, or setup refused while the
    /// account is signed in. That last one is usually the per-app iCloud
    /// switch, and then this save fails too; the ones that do arrive point at
    /// the container or its entitlements.
    static func isReportable(_ disposition: SyncErrorClassifier.Disposition) -> Bool {
        switch disposition {
        case .schemaRejected, .limitExceeded, .setupFailedWhileSignedIn:
            return true
        case .transient, .userActionable, .benign, .unknown:
            return false
        }
    }

    /// Never from tests or UI tests. Never when the store isn't mirroring:
    /// a local-only launch has no iCloud sync to report on. From DEBUG builds
    /// only on request, so everyday development failures stay out of the
    /// Development database.
    nonisolated static func isEnabled(
        isMirroring: Bool,
        isTestRun: Bool = AppRuntime.isRunningTests || AppRuntime.isUITesting,
        isDebugBuild: Bool = CloudKitPublicSyncFailureReporter.isDebugBuild,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        guard !isTestRun, isMirroring else { return false }
        return !isDebugBuild || arguments.contains(launchArgument)
    }

    @discardableResult
    func reportIfNeeded(_ classification: SyncErrorClassifier.Classification) -> Bool {
        // The allowance is claimed last, so a launch that can't send doesn't
        // use up the day's report.
        guard Self.isReportable(classification.disposition),
              isEnabled(),
              throttle.claim(classification.disposition) else { return false }

        let report = PublicSyncFailureReport(
            classification: classification,
            appVersion: appVersion,
            buildNumber: buildNumber,
            osVersion: osVersion,
            platform: platform
        )
        Self.dispatch(report, send: send)
        return true
    }

    #if DEBUG
    /// A public record type exists only once a record of it has been saved,
    /// and Development creates any missing type or field on demand, so the
    /// rejections that trigger real reports can't happen there. A DEBUG
    /// launch with the argument saves one sample with every field set: that
    /// creates PTSyncFailureReport in Development, and running it again
    /// checks that saves still work after the security roles change. Not
    /// throttled for that reason.
    static func sendDevelopmentSampleIfRequested(isMirroring: Bool) {
        guard isEnabled(isMirroring: isMirroring) else { return }
        let sample = PublicSyncFailureReport(
            disposition: developmentSampleDisposition,
            errorDomain: CKError.errorDomain,
            errorCode: 0,
            appVersion: currentAppVersion,
            buildNumber: currentBuildNumber,
            osVersion: currentOSVersion,
            platform: currentPlatform
        )
        dispatch(sample, send: { try await saveToPublicDatabase($0) })
    }
    #endif

    /// Fire and forget, off the main actor: the save can wait on the network
    /// for minutes, and a report is never worth holding up sync handling.
    nonisolated private static func dispatch(_ report: PublicSyncFailureReport, send: @escaping Send) {
        Task.detached(priority: .utility) {
            do {
                try await send(report)
                log.notice("Sent iCloud failure report \(report.disposition, privacy: .public)")
            } catch {
                // Public saves need a signed-in account, a network and the
                // record type deployed to Production, and any of them can be
                // missing. The day's allowance stays used, so a save that
                // keeps failing isn't retried on every export.
                let nsError = error as NSError
                log.error("Couldn't send iCloud failure report \(report.disposition, privacy: .public): \(nsError.domain, privacy: .public) \(nsError.code, privacy: .public)")
            }
        }
    }

    /// The container is created here, not at init, so tests and launches that
    /// never report never touch CloudKit.
    nonisolated static func saveToPublicDatabase(_ report: PublicSyncFailureReport) async throws {
        let database = CKContainer(identifier: containerIdentifier).publicCloudDatabase
        _ = try await database.save(report.makeRecord())
    }

    nonisolated static var currentAppVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    nonisolated static var currentBuildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
    }

    nonisolated static var currentOSVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    static var currentPlatform: String {
        #if os(macOS)
        return "macOS"
        #elseif canImport(UIKit)
        return UIDevice.current.userInterfaceIdiom == .pad ? "iPadOS" : "iOS"
        #else
        return "unknown"
        #endif
    }
}
