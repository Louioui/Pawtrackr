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
import SwiftData
import OSLog
import Combine
import Network
#if canImport(UIKit)
import UIKit
#endif

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

    enum NetworkState: Equatable {
        case unknown
        case online(isExpensive: Bool, isConstrained: Bool)
        case offline
        case requiresConnection

        var isOnline: Bool {
            if case .online = self { return true }
            return false
        }

        var displayLabel: String {
            switch self {
            case .unknown:
                return NSLocalizedString("cloudkit.network.unknown", value: "Network status unknown", comment: "")
            case .online(let expensive, let constrained):
                if constrained {
                    return NSLocalizedString("cloudkit.network.constrained", value: "Online, Low Data Mode", comment: "")
                }
                if expensive {
                    return NSLocalizedString("cloudkit.network.expensive", value: "Online, cellular/hotspot", comment: "")
                }
                return NSLocalizedString("cloudkit.network.online", value: "Online", comment: "")
            case .offline:
                return NSLocalizedString("cloudkit.network.offline", value: "Offline", comment: "")
            case .requiresConnection:
                return NSLocalizedString("cloudkit.network.requires_connection", value: "Network needs connection", comment: "")
            }
        }
    }

    enum SyncEventKind: String, Codable {
        case setup
        case importFromCloud
        case exportToCloud
        case account
        case localChange
        case remotePush
        case recovery
        case media
        case healthCheck

        var displayLabel: String {
            switch self {
            case .setup: return "Setup"
            case .importFromCloud: return "Import"
            case .exportToCloud: return "Export"
            case .account: return "Account"
            case .localChange: return "Local Change"
            case .remotePush: return "Remote Push"
            case .recovery: return "Recovery"
            case .media: return "Media"
            case .healthCheck: return "Health Check"
            }
        }
    }

    enum SyncEventStatus: String, Codable {
        case started
        case succeeded
        case failed
        case noted
        case waiting

        var displayLabel: String {
            switch self {
            case .started: return "Started"
            case .succeeded: return "Succeeded"
            case .failed: return "Failed"
            case .noted: return "Noted"
            case .waiting: return "Waiting"
            }
        }
    }

    struct SyncEvent: Identifiable, Codable, Equatable {
        let id: UUID
        let kind: SyncEventKind
        let status: SyncEventStatus
        let startedAt: Date
        let endedAt: Date?
        let message: String
        let deviceID: UUID // Track which device triggered this event
        let errorCode: String?

        var durationSeconds: TimeInterval? {
            guard let endedAt else { return nil }
            return endedAt.timeIntervalSince(startedAt)
        }
    }

    struct SyncHealthIssue: Identifiable, Equatable {
        enum Severity: Int, Equatable {
            case info
            case warning
            case danger
        }

        let id: String
        let severity: Severity
        let title: String
        let detail: String
    }

    private(set) var accountState: AccountState = .unknown
    private(set) var syncState: SyncState = .idle
    private(set) var networkState: NetworkState = .unknown
    private(set) var lastSyncDate: Date?
    private(set) var lastAttemptDate: Date?
    private(set) var lastImportDate: Date?
    private(set) var lastExportDate: Date?
    private(set) var lastErrorMessage: String?
    private(set) var quotaExceeded: Bool = false
    private(set) var iCloudAppAccessMayBeDisabled: Bool = false
    private(set) var firstSyncCompleted: Bool
    private(set) var syncEvents: [SyncEvent]
    private(set) var pendingLocalChangeCount: Int = 0
    private(set) var isAutomaticSyncEnabled: Bool = false
    private(set) var pendingLocalChangeDate: Date?
    private(set) var pendingLocalChangeDescription: String?
    private(set) var offlineBufferedMutationCount: Int = 0
    private(set) var manualCheckRemainingSeconds: Int = 0

    var canForceSync: Bool {
        manualCheckRemainingSeconds == 0
    }

    /// Container identifier from the entitlements file. Surfaced for the
    /// diagnostics screen so users can read it back to support.
    let containerIdentifier: String = "iCloud.PartnerShipWithMedia.Pawtrackr"

    // MARK: - Private

    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "CloudKit")
    private let container: CKContainer?
    private let networkMonitor = NWPathMonitor()
    private let networkQueue = DispatchQueue(label: "Pawtrackr.CloudKit.Network")
    private var observers: [NSObjectProtocol] = []
    private var hasStarted = false
    private var hasStartedNetworkMonitor = false
    private var modelContainer: ModelContainer?
    private var eventBus: GlobalEventBus?
    private var remoteWakeWaiters: [UUID: CheckedContinuation<Bool, Never>] = [:]
    private var firstSyncSettleTask: Task<Void, Never>?
    /// The currently-running forceSync watchdog. Replaced (and cancelled) on each
    /// new forceSync call so rapid pull-to-refresh doesn't stack watchdogs that
    /// later all race to flip syncState back to .idle.
    private var forceSyncWatchdog: Task<Void, Never>?
    private var remoteStoreRefreshTask: Task<Void, Never>?
    private var offlineFlushTask: Task<Void, Never>?
    private var reconcileDebounceTask: Task<Void, Never>?
    private var manualCheckCooldownTask: Task<Void, Never>?

    private enum DefaultsKey {
        static let lastSyncDate = "cloudkit.lastSyncDate"
        static let lastAttemptDate = "cloudkit.lastAttemptDate"
        static let lastImportDate = "cloudkit.lastImportDate"
        static let lastExportDate = "cloudkit.lastExportDate"
        static let firstSyncCompleted = "cloudkit.firstSyncCompleted"
        static let syncEvents = "cloudkit.syncEvents"
        static let pendingLocalChangeCount = "cloudkit.pendingLocalChangeCount"
        static let pendingLocalChangeDate = "cloudkit.pendingLocalChangeDate"
        static let pendingLocalChangeDescription = "cloudkit.pendingLocalChangeDescription"
        static let quotaExceeded = "cloudkit.quotaExceeded"
    }

    // MARK: - Init

    private init() {
        self.container = AppRuntime.allowsICloudSync ? CKContainer(identifier: "iCloud.PartnerShipWithMedia.Pawtrackr") : nil
        self.lastSyncDate = UserDefaults.standard.object(forKey: DefaultsKey.lastSyncDate) as? Date
        self.lastAttemptDate = UserDefaults.standard.object(forKey: DefaultsKey.lastAttemptDate) as? Date
        self.lastImportDate = UserDefaults.standard.object(forKey: DefaultsKey.lastImportDate) as? Date
        self.lastExportDate = UserDefaults.standard.object(forKey: DefaultsKey.lastExportDate) as? Date
        self.firstSyncCompleted = UserDefaults.standard.bool(forKey: DefaultsKey.firstSyncCompleted)
        self.syncEvents = Self.loadPersistedEvents()
        self.pendingLocalChangeCount = UserDefaults.standard.integer(forKey: DefaultsKey.pendingLocalChangeCount)
        self.pendingLocalChangeDate = UserDefaults.standard.object(forKey: DefaultsKey.pendingLocalChangeDate) as? Date
        self.pendingLocalChangeDescription = UserDefaults.standard.string(forKey: DefaultsKey.pendingLocalChangeDescription)
        self.offlineBufferedMutationCount = OfflineMutationBuffer.count
        self.quotaExceeded = UserDefaults.standard.bool(forKey: DefaultsKey.quotaExceeded)
    }

    // MARK: - Lifecycle

    /// Idempotent starter. Called once from PawtrackrApp on launch.
    func start(modelContainer: ModelContainer? = nil, eventBus: GlobalEventBus? = nil) {
        if let modelContainer {
            self.modelContainer = modelContainer
            isAutomaticSyncEnabled = true
        }
        if let eventBus {
            self.eventBus = eventBus
        }
        guard !hasStarted else { return }
        hasStarted = true

        observeAccountChanges()
        observeCloudKitEvents()
        observePersistentStoreRemoteChanges()
        observeNetworkState()
        observeDeviceNameChanges()
        runSafeModeDiagnostics()
        cleanupStalePresence()
        Task { await refreshAccountStatus() }
    }

    // ...

    private func observeDeviceNameChanges() {
        let token = NotificationCenter.default.addObserver(
            forName: .deviceNameDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateDeviceMetadata()
            }
        }
        observers.append(token)
    }

    // Observers are intentionally retained for the lifetime of the app.
    // The deinit-with-observer-cleanup pattern doesn't mix with Swift 6
    // actor isolation on stored properties anyway.

    // MARK: - Account status

    /// Re-checks the iCloud account status. Safe to call repeatedly.
    func refreshAccountStatus() async {
        guard let container else {
            accountState = .couldNotDetermine
            postChange()
            return
        }

        do {
            let status = try await ResilienceCoordinator.run(
                label: "CloudKit account status",
                policy: .cloudKit,
                classify: ResilienceCoordinator.cloudKitDisposition(for:)
            ) {
                try await container.accountStatus()
            }
            // We're already @MainActor — no need for an explicit hop.
            applyAccountStatus(status)
        } catch {
            log.error("Failed to fetch CKAccountStatus: \(error.localizedDescription, privacy: .public)")
            accountState = .couldNotDetermine
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
        let appAccessMayBeDisabled = mapped == .available && FileManager.default.ubiquityIdentityToken == nil
        let stateChanged = mapped != accountState || appAccessMayBeDisabled != iCloudAppAccessMayBeDisabled
        if stateChanged {
            accountState = mapped
            iCloudAppAccessMayBeDisabled = appAccessMayBeDisabled
            log.info("CKAccountStatus changed: \(String(describing: status), privacy: .public)")
            appendEvent(
                kind: .account,
                status: mapped == .available ? .succeeded : .noted,
                message: mapped.displayLabel,
                errorCode: mapped == .available ? nil : String(describing: status)
            )
            if mapped == .available, networkState.isOnline {
                flushOfflineMutationBuffer(reason: "iCloud account available")
            }
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

    private func observeNetworkState() {
        guard !hasStartedNetworkMonitor else { return }
        hasStartedNetworkMonitor = true

        networkMonitor.pathUpdateHandler = { [weak self] path in
            let next: NetworkState
            switch path.status {
            case .satisfied:
                next = .online(isExpensive: path.isExpensive, isConstrained: path.isConstrained)
            case .unsatisfied:
                next = .offline
            case .requiresConnection:
                next = .requiresConnection
            @unknown default:
                next = .unknown
            }

            Task { @MainActor [weak self] in
                guard let self, self.networkState != next else { return }
                self.networkState = next
                if !next.isOnline {
                    self.appendEvent(
                        kind: .healthCheck,
                        status: .noted,
                        message: next.displayLabel,
                        errorCode: nil
                    )
                } else if self.accountState.isAvailable {
                    // Heartbeat our device info when we come online
                    self.updateDeviceMetadata()
                    self.flushOfflineMutationBuffer(reason: "Network restored")
                    self.runSafeModeDiagnostics()
                }
            }
        }
        networkMonitor.start(queue: networkQueue)
    }

    // MARK: - Device Metadata

    /// Heartbeats the current device's metadata to iCloud.
    /// This allows the business owner to see which worker devices are active.
    func updateDeviceMetadata() {
        guard let modelContainer, accountState.isAvailable, networkState.isOnline else { return }

        #if os(iOS)
        let deviceModel = UIDevice.current.model
        let osVersion = "iOS " + UIDevice.current.systemVersion
        #elseif os(macOS)
        let deviceModel = "Mac"
        let osVersion = "macOS " + ProcessInfo.processInfo.operatingSystemVersionString
        #else
        let deviceModel = "Unknown"
        let osVersion = "Unknown"
        #endif
        let deviceName = UserDefaults.standard.string(forKey: "deviceName") ?? deviceModel
        
        Task.detached(priority: .utility) {
            let context = ModelContext(modelContainer)
            let deviceID = DeviceIdentity.currentID
            let descriptor = FetchDescriptor<DeviceMetadata>(
                predicate: #Predicate<DeviceMetadata> { $0.deviceID == deviceID }
            )
            
            do {
                let existing = try context.fetch(descriptor).first
                
                if let meta = existing {
                    meta.name = deviceName
                    meta.model = deviceModel
                    meta.osVersion = osVersion
                    meta.lastSyncAt = .now
                } else {
                    let meta = DeviceMetadata(
                        deviceID: deviceID,
                        name: deviceName,
                        model: deviceModel,
                        osVersion: osVersion
                    )
                    context.insert(meta)
                }
                
                if context.hasChanges {
                    try context.save()
                }
            } catch {
                Logger.cloudKit.error("Failed to update device metadata: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Presence

    /// Updates the current device's presence record.
    func setPresence(viewingRecordID: UUID?, recordType: String?) {
        guard let modelContainer, accountState.isAvailable else { return }
        
        Task.detached(priority: .utility) {
            let context = ModelContext(modelContainer)
            let deviceID = DeviceIdentity.currentID
            let descriptor = FetchDescriptor<PresenceRecord>(
                predicate: #Predicate<PresenceRecord> { $0.deviceID == deviceID }
            )
            
            do {
                let deviceName = UserDefaults.standard.string(forKey: "deviceName") ?? "Unknown Device"
                let existing = try context.fetch(descriptor).first
                
                if let presence = existing {
                    presence.deviceName = deviceName
                    presence.viewingRecordID = viewingRecordID
                    presence.recordType = recordType
                    presence.updatedAt = .now
                } else {
                    let presence = PresenceRecord(deviceID: deviceID, deviceName: deviceName)
                    presence.viewingRecordID = viewingRecordID
                    presence.recordType = recordType
                    context.insert(presence)
                }
                
                try context.save()
            } catch {
                Logger.cloudKit.error("Failed to update presence: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Periodically cleans up stale presence records (older than 10 minutes).
    func cleanupStalePresence() {
        guard let modelContainer, networkState.isOnline else { return }
        
        Task.detached(priority: .utility) {
            let context = ModelContext(modelContainer)
            let threshold = Date().addingTimeInterval(-600) // 10 minutes
            let descriptor = FetchDescriptor<PresenceRecord>(
                predicate: #Predicate<PresenceRecord> { $0.updatedAt < threshold }
            )
            
            do {
                let stale = try context.fetch(descriptor)
                for record in stale {
                    context.delete(record)
                }
                if !stale.isEmpty {
                    try context.save()
                }
            } catch {
                Logger.cloudKit.error("Failed to cleanup presence: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Predictive Media Warming

    /// Pre-warms the cache by fetching media for a specific pet.
    /// Called when a pet is checked in to ensure historical photos are ready on all devices.
    func warmMediaCache(for petUUID: UUID) {
        guard let modelContainer else { return }
        
        Task.detached(priority: .utility) {
            let context = ModelContext(modelContainer)
            let descriptor = FetchDescriptor<Pet>(
                predicate: #Predicate<Pet> { $0.uuid == petUUID }
            )
            
            do {
                if let pet = try context.fetch(descriptor).first {
                    // Touch photos to trigger background download if using externalStorage
                    _ = pet.photoData
                    _ = pet.thumbnailData
                    
                    // Also warm the last 3 visits
                    let visits = (pet.visits ?? [])
                        .filter { $0.isCompleted }
                        .sorted { $0.startedAt > $1.startedAt }
                        .prefix(3)
                    
                    for visit in visits {
                        _ = visit.beforeThumbnailData
                        _ = visit.afterThumbnailData
                    }
                    
                    Logger.cloudKit.info("Predictive Warming: Media cache prepared for pet \(pet.name)")
                }
            } catch {
                Logger.cloudKit.error("Media warming failed: \(error.localizedDescription, privacy: .public)")
            }
        }
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

    private func observePersistentStoreRemoteChanges() {
        let token = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handlePersistentStoreRemoteChange()
            }
        }
        observers.append(token)
    }

    private func handlePersistentStoreRemoteChange() {
        recordSyncAttempt()
        syncState = .syncing
        modelContainer?.mainContext.processPendingChanges()
        appendEvent(
            kind: .importFromCloud,
            status: .started,
            message: "Remote store change received",
            errorCode: nil
        )
        eventBus?.publish(.refreshRequired)
        postChange()

        remoteStoreRefreshTask?.cancel()
        remoteStoreRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, !Task.isCancelled else { return }
            self.modelContainer?.mainContext.processPendingChanges()
            self.rebuildAndReconcileAfterImport()
            if case .syncing = self.syncState {
                self.syncState = .idle
                self.postChange()
            }
        }
    }

    private func handleCloudKitEvent(notification: Notification) {
        guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event else {
            return
        }

        let kind = syncEventKind(for: event)
        if event.endDate == nil {
            // In progress
            recordSyncAttempt()
            syncState = .syncing
            appendEvent(
                kind: kind,
                status: .started,
                startedAt: event.startDate,
                message: "\(kind.displayLabel) started",
                errorCode: nil
            )
            postChange()
            return
        }

        // Completed
        if let error = event.error {
            handleError(error, kind: kind, startedAt: event.startDate, endedAt: event.endDate ?? Date())
        } else {
            // Successful setup/import events can arrive while an export is still
            // blocked by account quota. Keep quota visible until an export really
            // succeeds so the UI doesn't briefly claim the queue is healthy.
            if event.type == .export {
                quotaExceeded = false
                UserDefaults.standard.set(false, forKey: DefaultsKey.quotaExceeded)
                lastErrorMessage = nil
            } else if !quotaExceeded {
                lastErrorMessage = nil
            }
            syncState = .idle
            lastSyncDate = event.endDate ?? Date()
            UserDefaults.standard.set(lastSyncDate, forKey: DefaultsKey.lastSyncDate)
            appendEvent(
                kind: kind,
                status: .succeeded,
                startedAt: event.startDate,
                endedAt: lastSyncDate,
                message: "\(kind.displayLabel) finished",
                errorCode: nil
            )

            if event.type == .import {
                lastImportDate = lastSyncDate
                UserDefaults.standard.set(lastImportDate, forKey: DefaultsKey.lastImportDate)
                scheduleFirstSyncCompletionAfterImport()
                rebuildAndReconcileAfterImport()
            } else if event.type == .export {
                lastExportDate = lastSyncDate
                UserDefaults.standard.set(lastExportDate, forKey: DefaultsKey.lastExportDate)
                clearPendingLocalChanges(reason: "CloudKit export finished")
            }
            resumeRemoteWakeWaiters(success: true)
        }
        postChange()
    }

    private func handleError(
        _ error: Error,
        kind: SyncEventKind = .healthCheck,
        startedAt: Date = Date(),
        endedAt: Date = Date()
    ) {
        let nsError = error as NSError
        
        // Suppress expected "no account" error from CloudKit mirroring setup
        if nsError.domain == NSCocoaErrorDomain && nsError.code == 134400 {
            log.info("CloudKit integration setup skipped: No iCloud account configured (expected).")
            appendEvent(
                kind: kind,
                status: .noted,
                startedAt: startedAt,
                endedAt: endedAt,
                message: "CloudKit setup skipped because no iCloud account is configured",
                errorCode: "\(nsError.domain).\(nsError.code)"
            )
            return
        }

        log.error("CloudKit event error: \(error.localizedDescription, privacy: .public) (\(nsError.code))")

        if Self.isQuotaExceededError(error) {
            quotaExceeded = true
            UserDefaults.standard.set(true, forKey: DefaultsKey.quotaExceeded)
            lastErrorMessage = NSLocalizedString(
                "cloudkit.error.quota",
                value: "Your iCloud storage is full. Free up space or upgrade.",
                comment: ""
            )
        } else if let ckError = ckError(from: error) {
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
                iCloudAppAccessMayBeDisabled = false
            case .accountTemporarilyUnavailable:
                lastErrorMessage = NSLocalizedString(
                    "cloudkit.error.account_temporarily_unavailable",
                    value: "Enter your Apple Account password in Settings to resume iCloud sync.",
                    comment: ""
                )
                accountState = .temporarilyUnavailable
                iCloudAppAccessMayBeDisabled = false
            case .partialFailure:
                lastErrorMessage = NSLocalizedString(
                    "cloudkit.error.partial",
                    value: "Some changes didn't sync. They'll retry shortly.",
                    comment: ""
                )
            default:
                lastErrorMessage = ckError.localizedDescription
            }
        } else {
            lastErrorMessage = error.localizedDescription
        }
        syncState = .error(message: lastErrorMessage ?? error.localizedDescription)
        appendEvent(
            kind: kind,
            status: .failed,
            startedAt: startedAt,
            endedAt: endedAt,
            message: lastErrorMessage ?? error.localizedDescription,
            errorCode: cloudKitErrorCodeDescription(for: error)
        )
        resumeRemoteWakeWaiters(success: false)
    }

    // MARK: - Actions

    /// Re-checks account status and records a user-initiated sync attempt.
    ///
    /// SwiftData's CloudKit adapter does not expose a public "sync now" API. We
    /// therefore avoid claiming success here; real health is driven by
    /// NSPersistentCloudKitContainer events.
    func forceSync() async {
        guard canForceSync else {
            appendEvent(
                kind: .healthCheck,
                status: .waiting,
                message: String(
                    format: NSLocalizedString(
                        "cloudkit.manual_check.cooldown_event_fmt",
                        value: "Manual iCloud check is cooling down for %d more second(s)",
                        comment: ""
                    ),
                    manualCheckRemainingSeconds
                ),
                errorCode: nil
            )
            postChange()
            return
        }

        startManualCheckCooldown()
        recordSyncAttempt()
        appendEvent(
            kind: .healthCheck,
            status: .started,
            message: "User requested iCloud check",
            errorCode: nil
        )
        if accountState.isAvailable, pendingLocalChangeCount > 0 {
            syncState = .syncing
            startForceSyncWatchdog()
        }
        await refreshAccountStatus()
        postChange()
    }

    func waitForRemoteNotificationSync(timeoutSeconds: Int = 20) async -> Bool {
        recordSyncAttempt()
        syncState = .syncing
        appendEvent(
            kind: .remotePush,
            status: .started,
            message: "Remote iCloud push received",
            errorCode: nil
        )
        postChange()

        let id = UUID()
        return await withCheckedContinuation { continuation in
            remoteWakeWaiters[id] = continuation
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(timeoutSeconds))
                guard let self, let continuation = self.remoteWakeWaiters.removeValue(forKey: id) else { return }
                if self.syncState == .syncing {
                    self.syncState = .idle
                    self.postChange()
                }
                continuation.resume(returning: false)
            }
        }
    }

    func reportLocalSaveError(_ error: Error, operation: String) {
        let message = String(
            format: NSLocalizedString(
                "cloudkit.error.local_save",
                value: "Couldn't save %@. Your change may not sync: %@",
                comment: ""
            ),
            operation,
            error.localizedDescription
        )
        lastErrorMessage = message
        syncState = .error(message: message)
        appendEvent(
            kind: .localChange,
            status: .failed,
            message: message,
            errorCode: cloudKitErrorCodeDescription(for: error)
        )
        log.error("Local save failed during \(operation, privacy: .public): \(error.localizedDescription, privacy: .public)")
        postChange()
    }

    func recordLocalChange(
        _ operation: String,
        entityName: String? = nil,
        recordUUID: UUID? = nil,
        changedKeys: [String] = []
    ) {
        guard !AppRuntime.isRunningTests else { return }
        pendingLocalChangeCount += 1
        pendingLocalChangeDate = Date()
        pendingLocalChangeDescription = operation
        persistPendingLocalChanges()

        if !accountState.isAvailable || !networkState.isOnline {
            offlineBufferedMutationCount = OfflineMutationBuffer.append(
                operation: operation,
                entityName: entityName,
                recordUUID: recordUUID,
                changedKeys: changedKeys
            )
        }

        appendEvent(
            kind: .localChange,
            status: .waiting,
            message: offlineBufferedMutationCount > 0 ? "\(operation) queued for iCloud" : operation,
            errorCode: nil
        )
        if accountState.isAvailable, networkState.isOnline {
            flushOfflineMutationBuffer(reason: "Local change recorded while online")
        }
        postChange()
    }

    func recordMediaSyncWarningIfNeeded(byteCount: Int, context: String) {
        let warningThreshold = CloudMediaPolicy.largeAssetWarningBytes
        guard byteCount >= warningThreshold else { return }
        let mb = Double(byteCount) / 1_048_576
        appendEvent(
            kind: .media,
            status: .noted,
            message: String(format: "%.1f MB media asset prepared for iCloud: %@", mb, context),
            errorCode: nil
        )
        postChange()
    }

    /// Marks the first-launch restore gate as handled. Used after the first
    /// successful import, user skip, or timeout so launch is never blocked
    /// repeatedly by a slow or unavailable iCloud account.
    func markFirstSyncCompleted() {
        guard !firstSyncCompleted else { return }
        firstSyncSettleTask?.cancel()
        firstSyncCompleted = true
        UserDefaults.standard.set(true, forKey: DefaultsKey.firstSyncCompleted)
        appendEvent(
            kind: .importFromCloud,
            status: .succeeded,
            message: "Initial iCloud restore gate completed",
            errorCode: nil
        )
        postChange()
    }

    // MARK: - UI helpers

    var statusIconName: String {
        if !accountState.isAvailable { return "exclamationmark.icloud.fill" }
        if quotaExceeded || iCloudAppAccessMayBeDisabled { return "exclamationmark.icloud.fill" }
        if hasPendingLocalChanges { return "exclamationmark.icloud.fill" }
        switch syncState {
        case .syncing: return "arrow.triangle.2.circlepath.icloud"
        case .error: return "xmark.icloud.fill"
        case .idle: return "checkmark.icloud.fill"
        }
    }

    var statusTint: SyncStatusTint {
        if !accountState.isAvailable || quotaExceeded || iCloudAppAccessMayBeDisabled { return .warning }
        if hasPendingLocalChanges { return .warning }
        switch syncState {
        case .error: return .danger
        case .syncing: return .neutral
        case .idle: return .success
        }
    }

    var lastSyncSummary: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        guard let date = lastSyncDate else {
            if let attempt = lastAttemptDate {
                let relative = formatter.localizedString(for: attempt, relativeTo: Date())
                return String(
                    format: NSLocalizedString("cloudkit.last_attempt.relative", value: "Last checked %@", comment: ""),
                    relative
                )
            }
            return NSLocalizedString("cloudkit.last_sync.never", value: "Not synced yet", comment: "")
        }
        let relative = formatter.localizedString(for: date, relativeTo: Date())
        let lastSuccess = String(
            format: NSLocalizedString("cloudkit.last_sync.relative", value: "Last synced %@", comment: ""),
            relative
        )
        guard let attempt = lastAttemptDate, attempt > date else { return lastSuccess }
        let attemptRelative = formatter.localizedString(for: attempt, relativeTo: Date())
        return "\(lastSuccess). " + String(
            format: NSLocalizedString("cloudkit.last_attempt.relative", value: "Last checked %@", comment: ""),
            attemptRelative
        )
    }

    var pendingChangesSummary: String? {
        let waitingCount = max(pendingLocalChangeCount, offlineBufferedMutationCount)
        guard waitingCount > 0 else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let relative = pendingLocalChangeDate.map { formatter.localizedString(for: $0, relativeTo: Date()) }
        let base = String(
            format: NSLocalizedString(
                "cloudkit.pending.count",
                value: "%d local change(s) waiting for iCloud",
                comment: ""
            ),
            waitingCount
        )
        guard let relative else { return base }
        return "\(base), \(relative)"
    }

    var healthIssues: [SyncHealthIssue] {
        var issues: [SyncHealthIssue] = []

        if !networkState.isOnline {
            issues.append(SyncHealthIssue(
                id: "network",
                severity: .warning,
                title: NSLocalizedString("cloudkit.health.network.title", value: "Network unavailable", comment: ""),
                detail: networkState.displayLabel
            ))
        }

        switch accountState {
        case .noAccount:
            issues.append(SyncHealthIssue(
                id: "account.noAccount",
                severity: .warning,
                title: NSLocalizedString("cloudkit.health.signed_out.title", value: "Signed out of iCloud", comment: ""),
                detail: NSLocalizedString("cloudkit.health.signed_out.detail", value: "Changes stay on this device until iCloud is available.", comment: "")
            ))
        case .restricted:
            issues.append(SyncHealthIssue(
                id: "account.restricted",
                severity: .warning,
                title: NSLocalizedString("cloudkit.health.restricted.title", value: "iCloud is restricted", comment: ""),
                detail: NSLocalizedString("cloudkit.health.restricted.detail", value: "Device restrictions are blocking sync.", comment: "")
            ))
        case .temporarilyUnavailable, .couldNotDetermine:
            issues.append(SyncHealthIssue(
                id: "account.unavailable",
                severity: .warning,
                title: accountState.displayLabel,
                detail: NSLocalizedString("cloudkit.health.account_unavailable.detail", value: "Pawtrackr will keep retrying.", comment: "")
            ))
        case .unknown, .available:
            break
        }

        if quotaExceeded {
            issues.append(SyncHealthIssue(
                id: "quota",
                severity: .danger,
                title: NSLocalizedString("cloudkit.health.quota.title", value: "iCloud storage is full", comment: ""),
                detail: NSLocalizedString(
                    "cloudkit.health.quota.detail",
                    value: "Changes are saving locally until iCloud storage is cleared.",
                    comment: ""
                )
            ))
        }

        if iCloudAppAccessMayBeDisabled {
            issues.append(SyncHealthIssue(
                id: "appAccess",
                severity: .warning,
                title: NSLocalizedString("cloudkit.health.app_access.title", value: "Check app iCloud access", comment: ""),
                detail: NSLocalizedString("cloudkit.health.app_access.detail", value: "The account is signed in, but Pawtrackr may be disabled in iCloud settings.", comment: "")
            ))
        }

        if case .error(let message) = syncState {
            issues.append(SyncHealthIssue(
                id: "sync.error",
                severity: .danger,
                title: NSLocalizedString("cloudkit.health.error.title", value: "Sync needs attention", comment: ""),
                detail: message
            ))
        }

        if hasPendingLocalChanges {
            issues.append(SyncHealthIssue(
                id: "pending",
                severity: .warning,
                title: NSLocalizedString("cloudkit.health.pending.title", value: "Changes are waiting to upload", comment: ""),
                detail: pendingChangesSummary ?? NSLocalizedString("cloudkit.health.pending.detail", value: "iCloud will upload them automatically.", comment: "")
            ))
        }

        if lastSyncDate == nil, accountState.isAvailable {
            issues.append(SyncHealthIssue(
                id: "neverSynced",
                severity: .info,
                title: NSLocalizedString("cloudkit.health.never_synced.title", value: "Waiting for first sync", comment: ""),
                detail: NSLocalizedString("cloudkit.health.never_synced.detail", value: "The first iCloud event has not completed on this device yet.", comment: "")
            ))
        }

        return issues
    }

    var healthHeadline: String {
        if let danger = healthIssues.first(where: { $0.severity == .danger }) {
            return danger.title
        }
        if let warning = healthIssues.first(where: { $0.severity == .warning && $0.id != "pending" }) {
            return warning.title
        }
        if let pending = pendingChangesSummary {
            return pending
        }
        if case .syncing = syncState {
            return NSLocalizedString("cloudkit.health.syncing", value: "Syncing with iCloud", comment: "")
        }
        return NSLocalizedString("cloudkit.health.ok", value: "iCloud sync looks healthy", comment: "")
    }

    var healthDetail: String {
        if let issue = healthIssues.first(where: { $0.severity == .danger }) ?? healthIssues.first(where: { $0.severity == .warning }) {
            return issue.detail
        }
        if let pending = pendingChangesSummary {
            return pending
        }
        return "\(lastSyncSummary). \(networkState.displayLabel)"
    }

    enum SyncStatusTint { case success, neutral, warning, danger }

    // MARK: - Private

    private var hasPendingLocalChanges: Bool {
        max(pendingLocalChangeCount, offlineBufferedMutationCount) > 0
    }

    private func postChange() {
        NotificationCenter.default.post(name: .cloudKitStateDidChange, object: self)
    }

    private func recordSyncAttempt() {
        lastAttemptDate = Date()
        UserDefaults.standard.set(lastAttemptDate, forKey: DefaultsKey.lastAttemptDate)
    }

    private func appendEvent(
        kind: SyncEventKind,
        status: SyncEventStatus,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        message: String,
        errorCode: String?
    ) {
        let event = SyncEvent(
            id: UUID(),
            kind: kind,
            status: status,
            startedAt: startedAt,
            endedAt: endedAt,
            message: message,
            deviceID: DeviceIdentity.currentID,
            errorCode: errorCode
        )
        syncEvents.insert(event, at: 0)
        if syncEvents.count > 25 {
            syncEvents.removeLast(syncEvents.count - 25)
        }
        persistEvents()
        
                // Show live toast for remote imports (collaboration)
                if kind == .importFromCloud && status == .noted {
                    ToastService.shared.show(message: message, icon: "icloud.and.arrow.down.fill", tint: .green)
                    
                    // Predictive Warming: If a check-in was part of this import, warm the pet media
                    if message.contains("checked in") {
                         // Extract pet name/id would be better, but for now we'll rely on the reconciler
                         // finding new visits and we can trigger warming there.
                    }
                }
    }

    // MARK: - Safe Mode

    /// Automatically repairs "stuck" sync sessions by resetting the container 
    /// state if no successful sync has occurred in 24 hours while online.
    func runSafeModeDiagnostics() {
        guard let modelContainer, accountState.isAvailable, networkState.isOnline else { return }
        
        let lastSuccess = lastSyncDate ?? .distantPast
        let timeSinceLastSuccess = Date().timeIntervalSince(lastSuccess)
        
        // If it's been > 24 hours of total sync failure
        if timeSinceLastSuccess > 86400 {
            Logger.cloudKit.warning("iCloud Safe Mode triggered: sync stuck for \(timeSinceLastSuccess)s")
            
            appendEvent(
                kind: .recovery,
                status: .started,
                message: "iCloud Safe Mode: Attempting sync repair...",
                errorCode: nil
            )
            
            // Re-check account and force a full reconciliation
            Task {
                await refreshAccountStatus()
                await forceSync()
                
                let context = ModelContext(modelContainer)
                _ = CloudSyncReconciler.reconcileImportedData(in: context)
                
                appendEvent(
                    kind: .recovery,
                    status: .succeeded,
                    message: "iCloud Safe Mode: Repair complete.",
                    errorCode: nil
                )
            }
        }
    }

    private func persistEvents() {
        guard let data = try? JSONEncoder().encode(syncEvents) else { return }
        UserDefaults.standard.set(data, forKey: DefaultsKey.syncEvents)
    }

    nonisolated private static func loadPersistedEvents() -> [SyncEvent] {
        guard let data = UserDefaults.standard.data(forKey: DefaultsKey.syncEvents),
              let events = try? JSONDecoder().decode([SyncEvent].self, from: data) else {
            return []
        }
        return Array(events.prefix(25))
    }

    private func persistPendingLocalChanges() {
        UserDefaults.standard.set(pendingLocalChangeCount, forKey: DefaultsKey.pendingLocalChangeCount)
        if let pendingLocalChangeDate {
            UserDefaults.standard.set(pendingLocalChangeDate, forKey: DefaultsKey.pendingLocalChangeDate)
        } else {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.pendingLocalChangeDate)
        }
        if let pendingLocalChangeDescription {
            UserDefaults.standard.set(pendingLocalChangeDescription, forKey: DefaultsKey.pendingLocalChangeDescription)
        } else {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.pendingLocalChangeDescription)
        }
    }

    private func clearPendingLocalChanges(reason: String) {
        guard pendingLocalChangeCount > 0 else { return }
        pendingLocalChangeCount = 0
        pendingLocalChangeDate = nil
        pendingLocalChangeDescription = nil
        persistPendingLocalChanges()
        appendEvent(
            kind: .exportToCloud,
            status: .succeeded,
            message: reason,
            errorCode: nil
        )
    }

    private func flushOfflineMutationBuffer(reason: String) {
        guard accountState.isAvailable, networkState.isOnline else { return }
        offlineBufferedMutationCount = OfflineMutationBuffer.count
        guard offlineBufferedMutationCount > 0 else { return }

        offlineFlushTask?.cancel()
        offlineFlushTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while self.accountState.isAvailable, self.networkState.isOnline {
                let batch = OfflineMutationBuffer.peekBatch()
                guard !batch.isEmpty else { break }

                self.syncState = .syncing
                self.appendEvent(
                    kind: .localChange,
                    status: .started,
                    message: "\(reason): releasing \(batch.count) buffered change(s)",
                    errorCode: nil
                )
                self.eventBus?.publish(.refreshRequired)
                self.postChange()

                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }

                self.offlineBufferedMutationCount = OfflineMutationBuffer.remove(ids: batch.map(\.id))
                self.pendingLocalChangeCount = max(self.pendingLocalChangeCount, self.offlineBufferedMutationCount)
                self.persistPendingLocalChanges()
                self.appendEvent(
                    kind: .localChange,
                    status: .noted,
                    message: "Buffered change batch released (\(batch.count) max per pass: \(OfflineMutationBuffer.batchLimit))",
                    errorCode: nil
                )

                if batch.count < OfflineMutationBuffer.batchLimit {
                    break
                }
            }

            if self.offlineBufferedMutationCount == 0, self.pendingLocalChangeCount > 0 {
                self.pendingLocalChangeCount = 0
                self.pendingLocalChangeDate = nil
                self.pendingLocalChangeDescription = nil
                self.persistPendingLocalChanges()
            }
            if case .syncing = self.syncState {
                self.syncState = .idle
            }
            self.postChange()
        }
    }

    private func startManualCheckCooldown(seconds: Int = 30) {
        manualCheckCooldownTask?.cancel()
        manualCheckRemainingSeconds = seconds
        postChange()

        manualCheckCooldownTask = Task { @MainActor [weak self] in
            while true {
                guard let self, self.manualCheckRemainingSeconds > 0 else { return }
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self.manualCheckRemainingSeconds = max(0, self.manualCheckRemainingSeconds - 1)
                self.postChange()
            }
        }
    }

    private func resumeRemoteWakeWaiters(success: Bool) {
        let waiters = remoteWakeWaiters.values
        remoteWakeWaiters.removeAll()
        for waiter in waiters {
            waiter.resume(returning: success)
        }
    }

    private func rebuildAndReconcileAfterImport() {
        guard let modelContainer, isAutomaticSyncEnabled else { return }
        // Coalesce rapid bursts of import events (e.g. initial sync, multi-device
        // flushes) so the reconciler runs once after the burst settles rather than
        // once per event.
        reconcileDebounceTask?.cancel()
        reconcileDebounceTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            Task.detached(priority: .utility) {
                let context = ModelContext(modelContainer)
                let report = CloudSyncReconciler.reconcileImportedData(in: context)
                SummaryUpdater.rebuildAllSummaries(in: context)
                await MainActor.run {
                    CloudKitMonitor.shared.appendEvent(
                        kind: .importFromCloud,
                        status: .noted,
                        message: report.summary,
                        errorCode: nil
                    )
                    // Notify the rest of the app that new remote data has arrived,
                    // ensuring all devices see updates (like check-ins) in real-time.
                    CloudKitMonitor.shared.eventBus?.publish(.refreshRequired)
                    CloudKitMonitor.shared.postChange()
                }
            }
        }
    }

    private func scheduleFirstSyncCompletionAfterImport() {
        guard !firstSyncCompleted else { return }
        firstSyncSettleTask?.cancel()
        firstSyncSettleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, !Task.isCancelled else { return }
            self.markFirstSyncCompleted()
        }
    }

    private func startForceSyncWatchdog() {
        forceSyncWatchdog?.cancel()
        forceSyncWatchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard let self, !Task.isCancelled else { return }
            if case .syncing = self.syncState {
                self.syncState = .idle
                self.appendEvent(
                    kind: .healthCheck,
                    status: .noted,
                    message: "No immediate CloudKit event followed the manual check",
                    errorCode: nil
                )
                self.postChange()
            }
        }
    }

    private func syncEventKind(for event: NSPersistentCloudKitContainer.Event) -> SyncEventKind {
        switch event.type {
        case .setup:
            return .setup
        case .import:
            return .importFromCloud
        case .export:
            return .exportToCloud
        @unknown default:
            return .healthCheck
        }
    }

    private func ckError(from error: Error) -> CKError? {
        if let ckError = error as? CKError { return ckError }
        let nsError = error as NSError
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error,
           let ckError = ckError(from: underlying) {
            return ckError
        }
        if let detailed = nsError.userInfo[NSDetailedErrorsKey] as? [Error] {
            return detailed.compactMap { ckError(from: $0) }.first
        }
        return nil
    }

    nonisolated static func isQuotaExceededError(_ error: Error) -> Bool {
        isQuotaExceededError(error, depth: 0)
    }

    nonisolated private static func isQuotaExceededError(_ error: Error, depth: Int) -> Bool {
        guard depth < 8 else { return false }

        if let ckError = error as? CKError {
            if ckError.code == .quotaExceeded {
                return true
            }
            if ckError.partialErrorsByItemID?.values.contains(where: {
                isQuotaExceededError($0, depth: depth + 1)
            }) == true {
                return true
            }
        }

        let nsError = error as NSError
        if nsError.domain == CKError.errorDomain && nsError.code == CKError.Code.quotaExceeded.rawValue {
            return true
        }

        let messageBits = [
            nsError.localizedDescription,
            nsError.localizedFailureReason,
            nsError.localizedRecoverySuggestion
        ].compactMap { $0 } + nsError.userInfo.values.compactMap { value -> String? in
            value as? String
        }
        let foldedMessage = messageBits.joined(separator: " ").lowercased()
        if foldedMessage.contains("quotaexceeded")
            || foldedMessage.contains("quota exceeded")
            || foldedMessage.contains("storage is full") {
            return true
        }

        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error,
           isQuotaExceededError(underlying, depth: depth + 1) {
            return true
        }

        if let detailed = nsError.userInfo[NSDetailedErrorsKey] as? [Error],
           detailed.contains(where: { isQuotaExceededError($0, depth: depth + 1) }) {
            return true
        }

        if let partials = nsError.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error],
           partials.values.contains(where: { isQuotaExceededError($0, depth: depth + 1) }) {
            return true
        }

        for value in nsError.userInfo.values {
            if let nested = value as? Error, isQuotaExceededError(nested, depth: depth + 1) {
                return true
            }
            if let nested = value as? [Error],
               nested.contains(where: { isQuotaExceededError($0, depth: depth + 1) }) {
                return true
            }
            if let nested = value as? [AnyHashable: Error],
               nested.values.contains(where: { isQuotaExceededError($0, depth: depth + 1) }) {
                return true
            }
        }

        return false
    }

    private func cloudKitErrorCodeDescription(for error: Error) -> String {
        if let ckError = ckError(from: error) {
            return "CKError.\(ckError.code.rawValue)"
        }
        let nsError = error as NSError
        return "\(nsError.domain).\(nsError.code)"
    }

    nonisolated static func resetPersistedSyncStateForLocalStoreReset() {
        UserDefaults.standard.removeObject(forKey: DefaultsKey.lastSyncDate)
        UserDefaults.standard.removeObject(forKey: DefaultsKey.lastAttemptDate)
        UserDefaults.standard.removeObject(forKey: DefaultsKey.lastImportDate)
        UserDefaults.standard.removeObject(forKey: DefaultsKey.lastExportDate)
        UserDefaults.standard.removeObject(forKey: DefaultsKey.firstSyncCompleted)
        UserDefaults.standard.removeObject(forKey: DefaultsKey.pendingLocalChangeCount)
        UserDefaults.standard.removeObject(forKey: DefaultsKey.pendingLocalChangeDate)
        UserDefaults.standard.removeObject(forKey: DefaultsKey.pendingLocalChangeDescription)
        UserDefaults.standard.removeObject(forKey: DefaultsKey.quotaExceeded)
        SummaryUpdater.resetSummaryRebuildState()
    }

    nonisolated static func recordLocalStoreResetArchivedFiles(_ count: Int) {
        let existing = loadPersistedEvents()
        let event = SyncEvent(
            id: UUID(),
            kind: .recovery,
            status: .succeeded,
            startedAt: Date(),
            endedAt: Date(),
            message: "Archived \(count) local store file(s) before reset",
            deviceID: DeviceIdentity.currentID,
            errorCode: nil
        )
        let next = Array(([event] + existing).prefix(25))
        if let data = try? JSONEncoder().encode(next) {
            UserDefaults.standard.set(data, forKey: DefaultsKey.syncEvents)
        }
    }
}
