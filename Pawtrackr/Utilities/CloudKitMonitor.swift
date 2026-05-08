//
//  CloudKitMonitor.swift
//  Pawtrackr
//
//  Central observable that surfaces CloudKit account + sync state to the UI.
//  - Tracks CKAccountStatus changes (signed in / signed out / restricted)
//  - Mirrors NSPersistentCloudKitContainer events (import / export / setup)
//  - Exposes lastSyncDate, lastError, and a friendly summary string for UI
//  - Provides a forceSync() entry point (Settings + pull-to-refresh use it)
//
//  Underlying SwiftData runs on top of NSPersistentCloudKitContainer when
//  cloudKitDatabase: .automatic is set, so we observe its event notification
//  directly to drive the UI.
//

import Foundation
import CloudKit
import CoreData
import OSLog
import Combine

@MainActor
@Observable
final class CloudKitMonitor {
    // MARK: - Singleton

    static let shared = CloudKitMonitor()

    // MARK: - Public state

    enum AccountState: Equatable {
        case unknown
        case available
        case noAccount
        case restricted
        case temporarilyUnavailable
        case couldNotDetermine

        var isAvailable: Bool { self == .available }

        var displayLabel: String {
            switch self {
            case .unknown: return NSLocalizedString("cloudkit.account.checking", value: "Checking iCloud…", comment: "")
            case .available: return NSLocalizedString("cloudkit.account.available", value: "Signed in to iCloud", comment: "")
            case .noAccount: return NSLocalizedString("cloudkit.account.no_account", value: "Not signed in to iCloud", comment: "")
            case .restricted: return NSLocalizedString("cloudkit.account.restricted", value: "iCloud is restricted on this device", comment: "")
            case .temporarilyUnavailable: return NSLocalizedString("cloudkit.account.temporarily_unavailable", value: "iCloud temporarily unavailable", comment: "")
            case .couldNotDetermine: return NSLocalizedString("cloudkit.account.unknown", value: "iCloud status unknown", comment: "")
            }
        }
    }

    enum SyncState: Equatable {
        case idle
        case syncing
        case error(message: String)

        static func == (lhs: SyncState, rhs: SyncState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.syncing, .syncing): return true
            case let (.error(a), .error(b)): return a == b
            default: return false
            }
        }
    }

    private(set) var accountState: AccountState = .unknown
    private(set) var syncState: SyncState = .idle
    private(set) var lastSyncDate: Date?
    private(set) var lastErrorMessage: String?
    private(set) var quotaExceeded: Bool = false
    private(set) var firstSyncCompleted: Bool

    /// Container identifier from the entitlements file. Surfaced for the
    /// diagnostics screen so users can read it back to support.
    let containerIdentifier: String = "iCloud.PartnerShipWithMedia.Pawtrackr"

    // MARK: - Private

    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "CloudKit")
    private let container: CKContainer
    private var observers: [NSObjectProtocol] = []
    private var hasStarted = false
    /// The currently-running forceSync watchdog. Replaced (and cancelled) on each
    /// new forceSync call so rapid pull-to-refresh doesn't stack watchdogs that
    /// later all race to flip syncState back to .idle.
    private var forceSyncWatchdog: Task<Void, Never>?

    private enum DefaultsKey {
        static let lastSyncDate = "cloudkit.lastSyncDate"
        static let firstSyncCompleted = "cloudkit.firstSyncCompleted"
    }

    // MARK: - Init

    private init() {
        self.container = CKContainer(identifier: "iCloud.PartnerShipWithMedia.Pawtrackr")
        self.lastSyncDate = UserDefaults.standard.object(forKey: DefaultsKey.lastSyncDate) as? Date
        self.firstSyncCompleted = UserDefaults.standard.bool(forKey: DefaultsKey.firstSyncCompleted)
    }

    // MARK: - Lifecycle

    /// Idempotent starter. Called once from PawtrackrApp on launch.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        observeAccountChanges()
        observeCloudKitEvents()
        Task { await refreshAccountStatus() }
    }

    // No deinit: this is a process-wide singleton; tokens live for the
    // lifetime of the app. The deinit-with-observer-cleanup pattern doesn't
    // mix with Swift 6 actor isolation on stored properties anyway.

    // MARK: - Account status

    /// Re-checks the iCloud account status. Safe to call repeatedly.
    func refreshAccountStatus() async {
        do {
            let status = try await container.accountStatus()
            await MainActor.run { self.applyAccountStatus(status) }
        } catch {
            log.error("Failed to fetch CKAccountStatus: \(error.localizedDescription, privacy: .public)")
            await MainActor.run { self.accountState = .couldNotDetermine }
            postChange()
        }
    }

    private func applyAccountStatus(_ status: CKAccountStatus) {
        let mapped: AccountState
        switch status {
        case .available: mapped = .available
        case .noAccount: mapped = .noAccount
        case .restricted: mapped = .restricted
        case .temporarilyUnavailable: mapped = .temporarilyUnavailable
        case .couldNotDetermine: mapped = .couldNotDetermine
        @unknown default: mapped = .couldNotDetermine
        }
        if mapped != accountState {
            accountState = mapped
            log.info("CKAccountStatus changed: \(String(describing: status), privacy: .public)")
            postChange()
        }
    }

    private func observeAccountChanges() {
        let token = NotificationCenter.default.addObserver(
            forName: .CKAccountChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // queue: .main delivers on the main thread, but Swift 6 isolation
            // requires an explicit MainActor hop to call our isolated method.
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.refreshAccountStatus()
            }
        }
        observers.append(token)
    }

    // MARK: - Sync events (NSPersistentCloudKitContainer)

    private func observeCloudKitEvents() {
        let eventToken = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.handleCloudKitEvent(notification: notification)
            }
        }
        observers.append(eventToken)
    }

    private func handleCloudKitEvent(notification: Notification) {
        guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event else {
            return
        }

        if event.endDate == nil {
            // In progress
            syncState = .syncing
            postChange()
            return
        }

        // Completed
        if let error = event.error {
            handleError(error)
        } else {
            // Successful sync of any kind (setup / import / export)
            quotaExceeded = false
            lastErrorMessage = nil
            syncState = .idle
            lastSyncDate = event.endDate ?? Date()
            UserDefaults.standard.set(lastSyncDate, forKey: DefaultsKey.lastSyncDate)

            if event.type == .import {
                markFirstSyncCompleted()
            }
        }
        postChange()
    }

    private func handleError(_ error: Error) {
        let nsError = error as NSError
        log.error("CloudKit event error: \(error.localizedDescription, privacy: .public) (\(nsError.code))")

        if let ckError = error as? CKError {
            if isQuotaExceeded(ckError) {
                quotaExceeded = true
                lastErrorMessage = NSLocalizedString(
                    "cloudkit.error.quota",
                    value: "Your iCloud storage is full. Free up space or upgrade.",
                    comment: ""
                )
            } else {
                switch ckError.code {
                case .networkUnavailable, .networkFailure:
                    lastErrorMessage = NSLocalizedString(
                        "cloudkit.error.network",
                        value: "Can't reach iCloud — check your connection.",
                        comment: ""
                    )
                case .notAuthenticated:
                    lastErrorMessage = NSLocalizedString(
                        "cloudkit.error.signed_out",
                        value: "Sign in to iCloud in Settings to sync your data.",
                        comment: ""
                    )
                    accountState = .noAccount
                case .partialFailure:
                    lastErrorMessage = NSLocalizedString(
                        "cloudkit.error.partial",
                        value: "Some changes didn't sync. They'll retry shortly.",
                        comment: ""
                    )
                default:
                    lastErrorMessage = ckError.localizedDescription
                }
            }
        } else {
            lastErrorMessage = error.localizedDescription
        }
        syncState = .error(message: lastErrorMessage ?? error.localizedDescription)
    }

    // MARK: - Actions

    /// Re-checks account status and asks NSPersistentCloudKitContainer to fetch
    /// a fresh batch of records. Safe to call from pull-to-refresh.
    func forceSync() async {
        await refreshAccountStatus()
        // SwiftData / NSPCKC kicks off its own sync on save and on app launch.
        // The official "give me everything" trigger is to post the persistent
        // history wake notification. There is no public force API; observers
        // see no harm if we just re-invoke account status (the system will
        // schedule a fetch). For UI purposes we briefly flip to .syncing
        // so the user sees feedback.
        syncState = .syncing
        postChange()
        // Watchdog: if no event arrives within 10s, drop back to idle so the
        // spinner doesn't get stuck. Cancel any in-flight watchdog first so
        // rapid forceSync() calls don't stack.
        forceSyncWatchdog?.cancel()
        forceSyncWatchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            if Task.isCancelled { return }
            await MainActor.run {
                guard let self else { return }
                if self.syncState == .syncing {
                    self.syncState = .idle
                    self.postChange()
                }
            }
        }
    }

    /// Marks the first-launch restore gate as handled. Used after the first
    /// successful import, user skip, or timeout so launch is never blocked
    /// repeatedly by a slow or unavailable iCloud account.
    func markFirstSyncCompleted() {
        guard !firstSyncCompleted else { return }
        firstSyncCompleted = true
        UserDefaults.standard.set(true, forKey: DefaultsKey.firstSyncCompleted)
        postChange()
    }

    // MARK: - UI helpers

    var statusIconName: String {
        if !accountState.isAvailable { return "exclamationmark.icloud.fill" }
        if quotaExceeded { return "exclamationmark.icloud.fill" }
        switch syncState {
        case .syncing: return "arrow.triangle.2.circlepath.icloud"
        case .error: return "xmark.icloud.fill"
        case .idle: return "checkmark.icloud.fill"
        }
    }

    var statusTint: SyncStatusTint {
        if !accountState.isAvailable || quotaExceeded { return .warning }
        switch syncState {
        case .error: return .danger
        case .syncing: return .neutral
        case .idle: return .success
        }
    }

    var lastSyncSummary: String {
        guard let date = lastSyncDate else {
            return NSLocalizedString("cloudkit.last_sync.never", value: "Not synced yet", comment: "")
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let relative = formatter.localizedString(for: date, relativeTo: Date())
        return String(
            format: NSLocalizedString("cloudkit.last_sync.relative", value: "Last synced %@", comment: ""),
            relative
        )
    }

    enum SyncStatusTint { case success, neutral, warning, danger }

    // MARK: - Private

    private func postChange() {
        NotificationCenter.default.post(name: .cloudKitStateDidChange, object: self)
    }

    private func isQuotaExceeded(_ error: CKError) -> Bool {
        if error.code == .quotaExceeded {
            return true
        }
        return error.partialErrorsByItemID?.values.contains { partialError in
            (partialError as? CKError)?.code == .quotaExceeded
        } ?? false
    }
}
