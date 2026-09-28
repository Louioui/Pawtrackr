//
//  SyncHealthReducer.swift
//  Pawtrackr
//
//  Decides what the app may claim about this device's iCloud backup.
//
//  Why this exists: the toolbar checkmark, "Last synced" and the per-visit
//  badge used to turn green on any successful CloudKit event, imports included.
//  Imports can keep succeeding while every upload fails or never runs, so a
//  groomer can come to believe iCloud holds clients it never received.
//  Only a successful export proves data left the device, so every "backed up"
//  signal is derived here from exports alone.
//
//  A plain value type with no CloudKit, UserDefaults or actor dependencies, so
//  tests can drive it synchronously. CloudKitMonitor translates
//  NSPersistentCloudKitContainer events into `Event`s, persists `state`, and
//  supplies the live account/network conditions when it asks for a status.
//

import Foundation

struct SyncHealthReducer: Sendable, Equatable {
    enum EventKind: Sendable, Equatable {
        case setup
        case `import`
        case export
    }

    /// Raw values are `SyncErrorClassifier.Disposition.diagnosticName`, so the
    /// monitor converts with `FailureDisposition(rawValue: disposition.diagnosticName)`
    /// and this file stays free of CloudKit types.
    enum FailureDisposition: String, Codable, Sendable, CaseIterable {
        case transient
        case quotaExceeded = "userActionable.quotaExceeded"
        case notAuthenticated = "userActionable.notAuthenticated"
        case accountTemporarilyUnavailable = "userActionable.accountTemporarilyUnavailable"
        case userDeletedZone = "userActionable.userDeletedZone"
        case schemaRejected
        case limitExceeded
        case benign
        case setupFailedWhileSignedIn
        case unknown

        // A category added by a later build must not fail decoding of the whole
        // state: that blob is the only on-device evidence that uploads ever worked.
        init(from decoder: Decoder) throws {
            let rawValue = try decoder.singleValueContainer().decode(String.self)
            self = FailureDisposition(rawValue: rawValue) ?? .unknown
        }
    }

    enum Event: Sendable, Equatable {
        case started(EventKind, at: Date)
        case succeeded(EventKind, startedAt: Date, endedAt: Date)
        /// `disposition` is nil when the error wasn't classified; that still counts
        /// as a failure.
        case failed(EventKind, startedAt: Date, endedAt: Date, disposition: FailureDisposition?, code: String?)
    }

    enum AccountAvailability: Sendable, Equatable {
        /// The first account-status check hasn't returned yet.
        case unknown
        case available
        /// No account, or restricted: nothing can upload until the user acts.
        case signedOut
        /// Signed in, but CloudKit can't confirm the account right now.
        case temporarilyUnavailable
    }

    struct Conditions: Sendable, Equatable {
        var account: AccountAvailability
        var isOnline: Bool
        /// The store opened without CloudKit mirroring, so no export can ever run.
        var isLocalOnly: Bool

        init(account: AccountAvailability, isOnline: Bool, isLocalOnly: Bool = false) {
            self.account = account
            self.isOnline = isOnline
            self.isLocalOnly = isLocalOnly
        }
    }

    struct ExportHealth: Codable, Equatable, Sendable {
        var consecutiveFailures: Int = 0
        var firstFailureAt: Date?
        var lastFailureAt: Date?
        /// The most telling cause in the current streak. A transient, unknown or
        /// unclassified failure doesn't replace an earlier specific cause, because
        /// a schema rejection will still be there when the network comes back.
        var lastFailureDisposition: FailureDisposition?
        /// `SyncErrorClassifier.Classification.diagnosticCode` ("CKError.15"),
        /// kept with the disposition it explains.
        var lastFailureCode: String?

        var isFailing: Bool { consecutiveFailures > 0 }
    }

    struct State: Codable, Equatable, Sendable {
        /// Start of the newest successful export. Changes committed before this
        /// instant were part of an upload CloudKit accepted.
        var lastSuccessfulExportStartedAt: Date?
        var lastSuccessfulExportEndedAt: Date?
        var everExportedSuccessfully: Bool = false
        var lastImportEndedAt: Date?
        var exportHealth = ExportHealth()
        /// Newest local change no successful export has covered yet.
        var pendingLocalChangeDate: Date?
        /// Oldest uncovered local change. The grace period runs from here: measured
        /// from the newest change, a groomer saving every few minutes would stay
        /// "backed up" indefinitely while nothing uploads.
        var firstPendingLocalChangeDate: Date?
    }

    /// How long a local change may wait for its upload, while an upload is
    /// possible, before the device stops claiming to be backed up.
    static let gracePeriod: TimeInterval = 5 * 60

    private(set) var state: State

    /// Start of the export CloudKit is running right now. Kept out of `state`
    /// on purpose: persisted, a crash mid-export would leave "Uploading" on
    /// screen forever.
    private(set) var exportInFlightSince: Date?

    init(state: State = State()) {
        self.state = state
    }

    // MARK: - Inputs

    mutating func apply(_ event: Event) {
        switch event {
        case let .started(kind, at):
            if kind == .export {
                exportInFlightSince = at
            }

        case let .succeeded(kind, startedAt, endedAt):
            switch kind {
            case .export:
                recordExportSuccess(startedAt: startedAt, endedAt: endedAt)
            case .import:
                state.lastImportEndedAt = Self.later(state.lastImportEndedAt, endedAt)
            case .setup:
                // A working setup proves nothing left the device, and it must not
                // clear a failure only an upload can disprove.
                break
            }

        case let .failed(kind, _, endedAt, disposition, code):
            switch kind {
            case .export:
                exportInFlightSince = nil
                recordFailure(endedAt: endedAt, disposition: disposition, code: code)
            case .setup:
                // A signed-out setup failure (134400 without an account) is already
                // reported as .signedOut. Recording it would carry a stale streak
                // into the moment the groomer signs in.
                guard disposition != .notAuthenticated else { return }
                // Any other setup failure means mirroring didn't start, so nothing
                // can upload; it belongs in the upload record and only an upload
                // can clear it.
                recordFailure(endedAt: endedAt, disposition: disposition, code: code)
            case .import:
                // Downloads say nothing about whether this device's data is in iCloud.
                break
            }
        }
    }

    mutating func recordLocalChange(at date: Date) {
        if let covered = state.lastSuccessfulExportStartedAt, date <= covered { return }
        state.pendingLocalChangeDate = Self.later(state.pendingLocalChangeDate, date)
        state.firstPendingLocalChangeDate = Self.earlier(state.firstPendingLocalChangeDate, date)
    }

    // MARK: - Derived status

    /// Oldest local change no successful export has covered, if any.
    var oldestUncoveredLocalChange: Date? {
        guard let newest = state.pendingLocalChangeDate else { return nil }
        if let covered = state.lastSuccessfulExportStartedAt, newest <= covered { return nil }
        return state.firstPendingLocalChangeDate ?? newest
    }

    func backupStatus(conditions: Conditions, now: Date) -> BackupStatus {
        if conditions.isLocalOnly { return .localOnly }
        if conditions.account == .signedOut { return .signedOut }

        let health = state.exportHealth
        if health.isFailing {
            return .failing(
                since: health.firstFailureAt ?? health.lastFailureAt ?? now,
                disposition: health.lastFailureDisposition ?? .unknown
            )
        }
        if conditions.account == .unknown { return .unknown }

        let uncoveredSince = oldestUncoveredLocalChange
        // A background export with nothing new to carry shouldn't flicker the
        // checkmark away.
        if exportInFlightSince != nil, !state.everExportedSuccessfully || uncoveredSince != nil {
            return .uploading
        }

        guard state.everExportedSuccessfully, let coveredUpTo = state.lastSuccessfulExportStartedAt else {
            return .notBackedUp(localChangesSince: uncoveredSince)
        }
        guard let uncoveredSince else { return .backedUp(asOf: coveredUpTo) }

        // Uploads trail a save by seconds to minutes; the grace period covers that
        // lag only while an upload can actually happen.
        let uploadIsPossible = conditions.isOnline && conditions.account == .available
        if uploadIsPossible, now.timeIntervalSince(uncoveredSince) < Self.gracePeriod {
            return .backedUp(asOf: coveredUpTo)
        }
        return .notBackedUp(localChangesSince: uncoveredSince)
    }

    // MARK: - Private

    private mutating func recordExportSuccess(startedAt: Date, endedAt: Date) {
        exportInFlightSince = nil
        state.everExportedSuccessfully = true
        state.lastSuccessfulExportStartedAt = Self.later(state.lastSuccessfulExportStartedAt, startedAt)
        state.lastSuccessfulExportEndedAt = Self.later(state.lastSuccessfulExportEndedAt, endedAt)

        // Notifications can arrive out of order; an older success must not erase
        // a newer failure.
        let failureIsNewer = state.exportHealth.lastFailureAt.map { $0 > endedAt } ?? false
        if !failureIsNewer {
            state.exportHealth = ExportHealth()
        }

        guard let covered = state.lastSuccessfulExportStartedAt,
              let newest = state.pendingLocalChangeDate else { return }
        if newest <= covered {
            state.pendingLocalChangeDate = nil
            state.firstPendingLocalChangeDate = nil
        } else {
            // Something was saved after this export began. Everything before the
            // export's start is covered; the exact oldest leftover isn't known, so
            // report the earliest time it could be.
            state.firstPendingLocalChangeDate = Self.later(state.firstPendingLocalChangeDate, covered)
        }
    }

    private mutating func recordFailure(endedAt: Date, disposition: FailureDisposition?, code: String?) {
        // Conflicts are resolved and retried by the mirroring delegate itself. They
        // don't confirm an upload either, so pending changes simply stay pending.
        if disposition == .benign { return }
        if let lastSuccess = state.lastSuccessfulExportEndedAt, endedAt < lastSuccess { return }

        var health = state.exportHealth
        health.consecutiveFailures += 1
        health.firstFailureAt = Self.earlier(health.firstFailureAt, endedAt)
        health.lastFailureAt = Self.later(health.lastFailureAt, endedAt)

        let isVague = disposition.map { $0 == .transient || $0 == .unknown } ?? true
        let hasSpecificCause = health.lastFailureDisposition.map { $0 != .transient && $0 != .unknown } ?? false
        if !(isVague && hasSpecificCause) {
            health.lastFailureDisposition = disposition
            health.lastFailureCode = code
        }
        state.exportHealth = health
    }

    private static func later(_ current: Date?, _ candidate: Date) -> Date {
        guard let current else { return candidate }
        return max(current, candidate)
    }

    private static func earlier(_ current: Date?, _ candidate: Date) -> Date {
        guard let current else { return candidate }
        return min(current, candidate)
    }
}

/// What the app may claim about this device's iCloud backup. Only `.backedUp`
/// earns a checkmark.
enum BackupStatus: Sendable, Equatable {
    /// CloudKit mirroring isn't running on this device, so nothing can upload.
    case localOnly
    /// No usable iCloud account (signed out or restricted).
    case signedOut
    /// Uploads are failing. Only a successful export clears this.
    case failing(since: Date, disposition: SyncHealthReducer.FailureDisposition)
    /// Nothing from this device is confirmed in iCloud yet, or local changes
    /// have waited past the grace period. Data imported from another device may
    /// still be in iCloud; this only speaks for this device's own changes.
    case notBackedUp(localChangesSince: Date?)
    /// An export is running and may carry changes that aren't covered yet.
    case uploading
    /// Every local change made before `asOf` was part of an upload CloudKit
    /// accepted (the start of the newest successful export).
    case backedUp(asOf: Date)
    /// The iCloud account hasn't been checked yet.
    case unknown

    var isBackedUp: Bool {
        if case .backedUp = self { return true }
        return false
    }
}

// MARK: - Lenient decoding

// Hand-written so a blob written by an older or newer build still decodes:
// losing it would erase the only on-device evidence that uploads ever worked.
extension SyncHealthReducer.State {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lastSuccessfulExportStartedAt = try container.decodeIfPresent(Date.self, forKey: .lastSuccessfulExportStartedAt)
        lastSuccessfulExportEndedAt = try container.decodeIfPresent(Date.self, forKey: .lastSuccessfulExportEndedAt)
        everExportedSuccessfully = try container.decodeIfPresent(Bool.self, forKey: .everExportedSuccessfully)
            ?? (lastSuccessfulExportStartedAt != nil)
        lastImportEndedAt = try container.decodeIfPresent(Date.self, forKey: .lastImportEndedAt)
        exportHealth = try container.decodeIfPresent(SyncHealthReducer.ExportHealth.self, forKey: .exportHealth)
            ?? SyncHealthReducer.ExportHealth()
        pendingLocalChangeDate = try container.decodeIfPresent(Date.self, forKey: .pendingLocalChangeDate)
        firstPendingLocalChangeDate = try container.decodeIfPresent(Date.self, forKey: .firstPendingLocalChangeDate)
    }
}

extension SyncHealthReducer.ExportHealth {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        consecutiveFailures = try container.decodeIfPresent(Int.self, forKey: .consecutiveFailures) ?? 0
        firstFailureAt = try container.decodeIfPresent(Date.self, forKey: .firstFailureAt)
        lastFailureAt = try container.decodeIfPresent(Date.self, forKey: .lastFailureAt)
        lastFailureDisposition = try container.decodeIfPresent(
            SyncHealthReducer.FailureDisposition.self,
            forKey: .lastFailureDisposition
        )
        lastFailureCode = try container.decodeIfPresent(String.self, forKey: .lastFailureCode)
    }
}
