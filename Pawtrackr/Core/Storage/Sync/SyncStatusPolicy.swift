//
//  SyncStatusPolicy.swift
//  Pawtrackr
//
//  The rules CloudKitMonitor and the banners share for turning upload facts
//  into what the groomer sees: when a failure is bad enough to go red, when
//  a failure has to wait for the account check, what the failure log keeps,
//  and how the pre-1.0.3 UserDefaults keys carry over.
//
//  Kept as pure functions so tests can pin them without a live
//  NSPersistentCloudKitContainer, whose events can't be constructed.
//

import CloudKit
import CoreData
import Foundation

enum SyncStatusPolicy {
    /// Failures in a row after which a streak stops looking like a hiccup.
    static let severeFailureStreak = 3
    /// How long uploads may keep failing, while online, before it goes red.
    static let severeFailureDuration: TimeInterval = 60 * 60
    /// How long the account has to be available before "nothing from this
    /// device has reached iCloud" is worth saying. The first export after a
    /// launch or a sign-in can take a few minutes.
    static let neverUploadedAccountAge: TimeInterval = 10 * 60
    /// Uncovered local changes older than this, while an upload is possible,
    /// mean uploads have stalled rather than lagged.
    static let stalledUploadAge: TimeInterval = 24 * 60 * 60
    /// On the recovery screen, an upload older than this no longer counts as
    /// a recent copy in iCloud.
    static let recentUploadAge: TimeInterval = 24 * 60 * 60
    static let failureLogLimit = 20

    // MARK: - Severity

    /// Retrying can't fix these: the schema, the payload or the iCloud side
    /// has to change first, so the groomer has to hear about it right away.
    static func isRejection(_ disposition: SyncHealthReducer.FailureDisposition) -> Bool {
        switch disposition {
        case .schemaRejected, .limitExceeded, .setupFailedWhileSignedIn, .userDeletedZone:
            return true
        case .transient, .quotaExceeded, .notAuthenticated, .accountTemporarilyUnavailable, .benign, .unknown:
            return false
        }
    }

    /// Storage and account failures already have their own banner, with the
    /// action that fixes them. The generic red one would bury it.
    static func hasDedicatedBanner(_ disposition: SyncHealthReducer.FailureDisposition) -> Bool {
        switch disposition {
        case .quotaExceeded, .notAuthenticated, .accountTemporarilyUnavailable:
            return true
        default:
            return false
        }
    }

    /// True when the upload failures on record should be shown as serious
    /// (red) instead of as a passing warning. The streak and duration rules
    /// only count while online: a groomer on a plane is not being rejected.
    static func isSevereFailure(
        _ health: SyncHealthReducer.ExportHealth,
        isOnline: Bool,
        now: Date
    ) -> Bool {
        guard health.isFailing else { return false }
        if let disposition = health.lastFailureDisposition, isRejection(disposition) {
            return true
        }
        guard isOnline else { return false }
        if health.consecutiveFailures >= severeFailureStreak { return true }
        // Only failing that was seen counts toward the hour. A single failure
        // left over from last night would otherwise go red at the next launch
        // before this session had retried anything.
        if health.consecutiveFailures >= 2,
           let first = health.firstFailureAt, let last = health.lastFailureAt,
           last.timeIntervalSince(first) >= severeFailureDuration {
            return true
        }
        return false
    }

    /// Whether the red "iCloud isn't accepting Pawtrackr's data" banner shows.
    static func showsUploadRejectionBanner(
        status: BackupStatus,
        health: SyncHealthReducer.ExportHealth,
        isOnline: Bool,
        now: Date
    ) -> Bool {
        guard case .failing(_, let disposition) = status, !hasDedicatedBanner(disposition) else { return false }
        return isSevereFailure(health, isOnline: isOnline, now: now)
    }

    /// Waiting changes become a warning only once they outlive the upload
    /// grace period. A device that never uploaded is reported not backed up
    /// straight away, since there's no earlier backup to fall back on, but its
    /// first saves still get the grace period before anything turns orange.
    static func isPendingPastGrace(since: Date, now: Date) -> Bool {
        now.timeIntervalSince(since) >= SyncHealthReducer.gracePeriod
    }

    /// "Nothing from this device has reached iCloud yet" is only fair once
    /// there is something to upload and the account has had time to try.
    static func showsNeverUploadedWarning(
        state: SyncHealthReducer.State,
        knownClientCount: Int,
        accountAvailableSince: Date?,
        now: Date
    ) -> Bool {
        guard !state.everExportedSuccessfully, !state.exportHealth.isFailing, knownClientCount > 0,
              let accountAvailableSince else { return false }
        return now.timeIntervalSince(accountAvailableSince) >= neverUploadedAccountAge
    }

    /// Whether the recovery screen warns that a reset leaves the app empty.
    /// There's no account or network to check there, only the persisted
    /// record, so anything short of a recent, unchallenged upload warns:
    /// a failure since, edits no upload has covered, or a device that fell
    /// back to local-only. A recent upload still only says some export
    /// succeeded, not that every client made it, which is why the copy says
    /// "from this device".
    static func lacksRecentUpload(
        _ state: SyncHealthReducer.State,
        isLocalOnlyFallback: Bool = false,
        now: Date
    ) -> Bool {
        guard let uploadedAt = state.lastSuccessfulExportEndedAt else { return true }
        if isLocalOnlyFallback || state.exportHealth.isFailing { return true }
        if SyncHealthReducer(state: state).oldestUncoveredLocalChange != nil { return true }
        return now.timeIntervalSince(uploadedAt) > recentUploadAge
    }

    // MARK: - Classification

    /// The mirroring delegate reports 134400 both for a signed-out device and
    /// for a setup that failed while signed in. Until CKContainer has answered,
    /// classifying it would be a guess, so the monitor holds it back.
    static func needsAccountStatus(_ error: Error) -> Bool {
        SyncErrorClassifier.classify(error, accountAvailable: true).disposition == .setupFailedWhileSignedIn
    }

    static func failureDisposition(
        for classification: SyncErrorClassifier.Classification
    ) -> SyncHealthReducer.FailureDisposition {
        SyncHealthReducer.FailureDisposition(rawValue: classification.disposition.diagnosticName) ?? .unknown
    }

    static func reducerKind(for type: NSPersistentCloudKitContainer.EventType) -> SyncHealthReducer.EventKind? {
        switch type {
        case .setup: return .setup
        case .import: return .import
        case .export: return .export
        @unknown default: return nil
        }
    }

    // MARK: - Status deadlines

    /// The next moment the backup status can change with nothing else
    /// happening: a pending change outgrows the grace period, a failure
    /// streak turns an hour old, or the account turns ten minutes old.
    /// The monitor sleeps until then instead of polling.
    static func nextStatusDeadline(
        oldestUncoveredLocalChange: Date?,
        health: SyncHealthReducer.ExportHealth,
        accountAvailableSince: Date?,
        now: Date
    ) -> Date? {
        var candidates: [Date] = []
        if let oldestUncoveredLocalChange {
            candidates.append(oldestUncoveredLocalChange.addingTimeInterval(SyncHealthReducer.gracePeriod))
        }
        if health.isFailing, let since = health.firstFailureAt {
            candidates.append(since.addingTimeInterval(severeFailureDuration))
        }
        if let accountAvailableSince {
            candidates.append(accountAvailableSince.addingTimeInterval(neverUploadedAccountAge))
        }
        return candidates.filter { $0 > now }.min()
    }

    // MARK: - Pending changes

    /// Tint for a "waiting changes" count. Zero waiting only earns the
    /// success color when uploads are running and the last one covered
    /// everything: with iCloud off, or nothing confirmed yet, an empty queue
    /// proves nothing.
    static func pendingTint(
        waitingCount: Int,
        isMirroring: Bool,
        status: BackupStatus
    ) -> CloudKitMonitor.SyncStatusTint {
        if waitingCount > 0 { return .warning }
        return isMirroring && status.isBackedUp ? .success : .neutral
    }

    // MARK: - Failure log

    /// Newest first, capped, so the failures survive the 25-entry event ring
    /// that routine imports rotate through in minutes.
    static func appending(
        _ record: SyncFailureRecord,
        to log: [SyncFailureRecord],
        limit: Int = failureLogLimit
    ) -> [SyncFailureRecord] {
        Array(([record] + log).prefix(max(0, limit)))
    }

    // MARK: - Pre-1.0.3 keys

    struct LegacySyncDefaults: Equatable {
        var lastExportDate: Date?
        var lastImportDate: Date?
        var lastAttemptDate: Date?
        var pendingLocalChangeCount: Int = 0
        var pendingLocalChangeDate: Date?
        var quotaExceeded: Bool = false
    }

    /// Builds the reducer state from the keys older builds wrote.
    /// `lastExportDate` held an export's end date, so it stands in for the
    /// start too; changes saved during that one export may be over-claimed.
    static func migratedState(from legacy: LegacySyncDefaults, now: Date) -> SyncHealthReducer.State {
        var reducer = SyncHealthReducer()
        if let exported = legacy.lastExportDate {
            reducer.apply(.succeeded(.export, startedAt: exported, endedAt: exported))
        }
        if let imported = legacy.lastImportDate {
            reducer.apply(.succeeded(.import, startedAt: imported, endedAt: imported))
        }
        if legacy.pendingLocalChangeCount > 0, let pending = legacy.pendingLocalChangeDate {
            reducer.recordLocalChange(at: pending)
        }
        if legacy.lastExportDate != nil {
            // Older builds cleared their pending counter without uploading
            // (the offline flush zeroed it), so the old export date can't
            // vouch for everything saved since. The first upload after the
            // update has to; the launch heartbeat writes something, so one
            // follows within seconds when iCloud works.
            reducer.recordLocalChange(at: now)
        }
        if legacy.quotaExceeded {
            // The old flag only cleared on a successful export, so the quota
            // failure came after the last one. The exact time wasn't kept.
            let failedAt: Date
            if let attempt = legacy.lastAttemptDate, attempt > (legacy.lastExportDate ?? .distantPast) {
                failedAt = attempt
            } else {
                failedAt = now
            }
            reducer.apply(.failed(
                .export,
                startedAt: failedAt,
                endedAt: failedAt,
                disposition: .quotaExceeded,
                code: "CKError.\(CKError.Code.quotaExceeded.rawValue)"
            ))
        }
        return reducer.state
    }
}

/// One upload or setup failure, kept outside the event ring so support can
/// still see it after a day of routine imports.
struct SyncFailureRecord: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let occurredAt: Date
    let kind: CloudKitMonitor.SyncEventKind
    /// `SyncErrorClassifier.Disposition.diagnosticName`.
    let disposition: String
    /// `SyncErrorClassifier.Classification.diagnosticCode`, e.g. "CKError.12".
    let code: String
    /// CloudKit's own wording. It can name record types, so it stays in
    /// on-device diagnostics and support reports the groomer sends herself,
    /// never in telemetry.
    let serverMessage: String?

    init(
        id: UUID = UUID(),
        occurredAt: Date,
        kind: CloudKitMonitor.SyncEventKind,
        disposition: String,
        code: String,
        serverMessage: String?
    ) {
        self.id = id
        self.occurredAt = occurredAt
        self.kind = kind
        self.disposition = disposition
        self.code = code
        self.serverMessage = serverMessage
    }
}

/// What the groomer reads about a failure. Keys match
/// `SyncErrorClassifier.Classification.userMessageKey`; they're spelled out
/// here so the localization check can see them.
enum SyncFailureCopy {
    /// A partial failure (CKError 2) that reached the app with no per-record
    /// errors inside can't be classified; the mirroring delegate often passes
    /// it on stripped. Full iCloud storage is its most common cause, so the
    /// red state says so, without claiming it. Returns nil for anything else.
    static func storageHint(for health: SyncHealthReducer.ExportHealth) -> String? {
        guard health.isFailing,
              health.lastFailureDisposition == .unknown,
              health.lastFailureCode == "CKError.\(CKError.Code.partialFailure.rawValue)" else { return nil }
        return AppLocalization.localized(
            "cloudkit.banner.rejected.storage_hint",
            value: "The most common cause is full iCloud storage."
        )
    }

    /// Title for the red state. "Isn't accepting" is only true for a
    /// rejection; a streak of timeouts or throttling that went red says so.
    static func severeTitle(for disposition: SyncHealthReducer.FailureDisposition) -> String {
        SyncStatusPolicy.isRejection(disposition)
            ? AppLocalization.localized("cloudkit.banner.rejected.title", value: "iCloud isn't accepting Pawtrackr's data")
            : AppLocalization.localized("cloudkit.banner.failing.title", value: "iCloud uploads keep failing")
    }

    static func message(for classification: SyncErrorClassifier.Classification) -> String? {
        message(
            for: SyncStatusPolicy.failureDisposition(for: classification),
            isNetwork: classification.userMessageKey == "cloudkit.error.network"
        )
    }

    static func message(for disposition: SyncHealthReducer.FailureDisposition, isNetwork: Bool) -> String? {
        switch disposition {
        case .transient where isNetwork:
            return AppLocalization.localized("cloudkit.error.network", value: "Can't reach iCloud — check your connection.")
        case .transient:
            // Only an all-transient failure earns the promise of a retry.
            return AppLocalization.localized("cloudkit.error.partial", value: "Some changes didn't sync. They'll retry shortly.")
        case .quotaExceeded:
            return AppLocalization.localized("cloudkit.error.quota", value: "Your iCloud storage is full. Free up space or upgrade.")
        case .notAuthenticated:
            return AppLocalization.localized("cloudkit.error.signed_out", value: "Sign in to iCloud in Settings to sync your data.")
        case .accountTemporarilyUnavailable:
            return AppLocalization.localized(
                "cloudkit.error.account_temporarily_unavailable",
                value: "Enter your Apple Account password in Settings to resume iCloud sync."
            )
        case .userDeletedZone:
            return AppLocalization.localized(
                "cloudkit.error.user_deleted_zone",
                value: "Pawtrackr's data was deleted from iCloud. The clients on this device are now the only copy, so don't delete the app."
            )
        case .schemaRejected:
            return AppLocalization.localized(
                "cloudkit.error.schema_rejected",
                value: "iCloud is rejecting changes from this version of Pawtrackr. Retrying won't fix it, so send the details to support."
            )
        case .limitExceeded:
            return AppLocalization.localized(
                "cloudkit.error.limit_exceeded",
                value: "Some records are too large for iCloud to accept. Retrying won't fix it, so send the details to support."
            )
        case .setupFailedWhileSignedIn:
            return AppLocalization.localized(
                "cloudkit.error.setup_failed",
                value: "iCloud sync couldn't start even though you're signed in. Check that Pawtrackr is turned on for iCloud in Settings, then reopen the app."
            )
        case .benign:
            return nil
        case .unknown:
            return AppLocalization.localized(
                "cloudkit.error.generic",
                value: "Some changes haven't reached iCloud. If this keeps happening, send the details to support."
            )
        }
    }

    /// Signed out, for the banner and the health detail. "Only on this
    /// device" was wrong: signing out can remove the local copy of synced
    /// data, and what already reached iCloud comes back on sign-in.
    static var signedOutMessage: String {
        AppLocalization.localized(
            "cloudkit.signed_out.message",
            value: "iCloud is off. Clients already uploaded come back when you sign in with the same Apple Account. Changes made now stay on this device."
        )
    }
}

/// The short label beside the status headline: pills and metric cards.
/// It comes from the backup status alone, so it can't say "Ready" or
/// "Healthy" while the headline says nothing has reached iCloud.
enum BackupStatusLabel: Equatable, Sendable {
    case backedUp
    case uploading
    case notBackedUp
    case needsAttention
    case iCloudOff
    case checkingAccount

    init(_ status: BackupStatus) {
        switch status {
        case .backedUp: self = .backedUp
        case .uploading: self = .uploading
        case .notBackedUp: self = .notBackedUp
        case .failing: self = .needsAttention
        case .signedOut, .localOnly: self = .iCloudOff
        case .unknown: self = .checkingAccount
        }
    }

    var title: String {
        switch self {
        case .backedUp:
            return AppLocalization.localized("cloudkit.status.backed_up", value: "Backed up")
        case .uploading:
            return AppLocalization.localized("cloudkit.status.uploading", value: "Uploading")
        case .notBackedUp:
            return AppLocalization.localized("cloudkit.status.not_backed_up", value: "Not backed up yet")
        case .needsAttention:
            return AppLocalization.localized("cloudkit.status.needs_attention", value: "Needs attention")
        case .iCloudOff:
            return AppLocalization.localized("cloudkit.status.icloud_off", value: "iCloud off")
        case .checkingAccount:
            return AppLocalization.localized("cloudkit.status.checking_account", value: "Checking account")
        }
    }
}

extension BackupStatus {
    /// English, for support reports.
    var diagnosticDescription: String {
        switch self {
        case .localOnly: return "local only (mirroring not running)"
        case .signedOut: return "signed out"
        case let .failing(since, disposition): return "failing since \(since.formatted()) (\(disposition.rawValue))"
        case .notBackedUp(let since): return "not backed up" + (since.map { ", local changes since \($0.formatted())" } ?? "")
        case .uploading: return "uploading"
        case .backedUp(let asOf): return "backed up as of \(asOf.formatted())"
        case .unknown: return "unknown (account not checked yet)"
        }
    }
}
