//
//  SyncFailureReporting.swift
//  Pawtrackr
//
//  The seam through which the developer hears that iCloud is refusing
//  Pawtrackr's uploads, instead of learning it from a groomer who lost data.
//
//  Only failures retrying can't fix are reported, and each at most once a day
//  per reporter. A report carries the classification and versions, never
//  client data or CloudKit's server message (which can name record types and
//  IDs).
//
//  Two reporters run side by side: one writes to the local log through
//  TelemetryService, the other saves a record to the app's CloudKit public
//  database (CloudKitPublicSyncFailureReporter), which is the only place the
//  developer can read reports today.
//

import Foundation

@MainActor
protocol SyncFailureReporting: AnyObject {
    /// Returns true when a report was sent.
    @discardableResult
    func reportIfNeeded(_ classification: SyncErrorClassifier.Classification) -> Bool
}

/// Hands each failure to every reporter. Each one applies its own rules and
/// its own daily allowance, so one declining never silences another.
@MainActor
final class CompositeSyncFailureReporter: SyncFailureReporting {
    private let reporters: [SyncFailureReporting]

    init(_ reporters: [SyncFailureReporting]) {
        self.reporters = reporters
    }

    @discardableResult
    func reportIfNeeded(_ classification: SyncErrorClassifier.Classification) -> Bool {
        reporters.reduce(false) { sent, reporter in
            reporter.reportIfNeeded(classification) || sent
        }
    }
}

/// When each disposition was last reported, persisted so the allowance
/// survives relaunches. An upload rejection repeats on every export retry;
/// without this, one broken schema would report every few minutes.
struct SyncFailureReportThrottle {
    static let minimumInterval: TimeInterval = 24 * 60 * 60

    private let keyPrefix: String
    private let defaults: UserDefaults
    private let now: () -> Date

    init(keyPrefix: String, defaults: UserDefaults, now: @escaping () -> Date) {
        self.keyPrefix = keyPrefix
        self.defaults = defaults
        self.now = now
    }

    /// Uses today's allowance for `disposition`. Returns false when it's
    /// already used.
    func claim(_ disposition: SyncErrorClassifier.Disposition) -> Bool {
        let key = keyPrefix + disposition.diagnosticName
        let current = now()
        // A clock set backwards shouldn't silence reports until it catches up.
        if let lastSent = defaults.object(forKey: key) as? Date,
           lastSent <= current,
           current.timeIntervalSince(lastSent) < Self.minimumInterval {
            return false
        }
        defaults.set(current, forKey: key)
        return true
    }
}

struct SyncFailureReport: Equatable, Sendable {
    let disposition: String
    let innermostDomain: String
    let innermostCode: Int
    let appVersion: String
    let osVersion: String

    init(classification: SyncErrorClassifier.Classification, appVersion: String, osVersion: String) {
        self.disposition = classification.disposition.diagnosticName
        self.innermostDomain = classification.innermostDomain
        self.innermostCode = classification.innermostCode
        self.appVersion = appVersion
        self.osVersion = osVersion
    }

    var parameters: [String: String] {
        [
            "disposition": disposition,
            "domain": innermostDomain,
            "code": String(innermostCode),
            "app_version": appVersion,
            "os_version": osVersion
        ]
    }
}

@MainActor
final class TelemetrySyncFailureReporter: SyncFailureReporting {
    static let eventName = "icloud_upload_rejected"
    private static let lastSentKeyPrefix = "cloudkit.failureReport.lastSent."

    private let throttle: SyncFailureReportThrottle
    private let appVersion: String
    private let osVersion: String
    private let send: (String, [String: String]) -> Void

    init(
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        appVersion: String = TelemetrySyncFailureReporter.currentAppVersion,
        osVersion: String = TelemetrySyncFailureReporter.currentOSVersion,
        send: @escaping (String, [String: String]) -> Void = { event, parameters in
            TelemetryService.shared.track(event: event, parameters: parameters)
        }
    ) {
        self.throttle = SyncFailureReportThrottle(keyPrefix: Self.lastSentKeyPrefix, defaults: defaults, now: now)
        self.appVersion = appVersion
        self.osVersion = osVersion
        self.send = send
    }

    /// Transient, account and quota failures reach the groomer through the UI
    /// and fix themselves or need her action, so they aren't reported.
    static func isReportable(_ disposition: SyncErrorClassifier.Disposition) -> Bool {
        switch disposition {
        case .schemaRejected, .limitExceeded:
            return true
        case .transient, .userActionable, .benign, .setupFailedWhileSignedIn, .unknown:
            return false
        }
    }

    @discardableResult
    func reportIfNeeded(_ classification: SyncErrorClassifier.Classification) -> Bool {
        guard Self.isReportable(classification.disposition),
              throttle.claim(classification.disposition) else { return false }

        let report = SyncFailureReport(classification: classification, appVersion: appVersion, osVersion: osVersion)
        send(Self.eventName, report.parameters)
        return true
    }

    nonisolated static var currentAppVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info?["CFBundleVersion"] as? String ?? "unknown"
        return "\(version)-\(build)"
    }

    nonisolated static var currentOSVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        #if os(macOS)
        let platform = "macOS"
        #else
        let platform = "iOS"
        #endif
        return "\(platform) \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
}
