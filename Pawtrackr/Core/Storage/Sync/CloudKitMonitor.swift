//
//  CloudKitMonitor.swift
//  Pawtrackr
//
//  Central observable that surfaces CloudKit account + sync state to the UI.
//  - Tracks CKAccountStatus changes (signed in / signed out / restricted)
//  - Mirrors NSPersistentCloudKitContainer events (import / export / setup)
//  - Derives what the app may claim about iCloud backup from exports alone,
//    through SyncHealthReducer: imports and setup prove nothing left the device
//  - Keeps upload failures visible until an upload succeeds
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

    /// How this launch's store relates to CloudKit. PawtrackrApp.init sets it
    /// before any view mounts, so the first frame already tells the truth.
    enum Mode: Equatable {
        /// SwiftData opened the store with `.automatic` mirroring.
        case mirroring
        /// Mirroring failed to start, so the store opened local-only. Nothing
        /// uploads until a later launch starts it. `since` is when this run of
        /// local-only launches began.
        case localOnlyFallback(error: String, since: Date)
        /// iCloud is off by design for this run (tests, in-memory stores).
        case disabled

        var isMirroring: Bool { self == .mirroring }

        var isLocalOnlyFallback: Bool {
            if case .localOnlyFallback = self { return true }
            return false
        }

        /// Content-free, for logs; the fallback error can carry file paths.
        var diagnosticName: String {
            switch self {
            case .mirroring: return "mirroring"
            case .localOnlyFallback: return "localOnlyFallback"
            case .disabled: return "disabled"
            }
        }
    }

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

        var backupAvailability: SyncHealthReducer.AccountAvailability {
            switch self {
            case .unknown: return .unknown
            case .available: return .available
            case .noAccount, .restricted: return .signedOut
            case .temporarilyUnavailable, .couldNotDetermine: return .temporarilyUnavailable
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

    private(set) var mode: Mode
    private(set) var accountState: AccountState = .unknown
    private(set) var networkState: NetworkState = .unknown
    /// Any successful CloudKit event, imports included. Diagnostics only: it
    /// says nothing about whether this device's data reached iCloud.
    private(set) var lastSyncDate: Date?
    private(set) var lastAttemptDate: Date?
    private(set) var lastImportDate: Date?
    private(set) var lastExportDate: Date?
    /// The unresolved failure to show. An upload failure stays until an
    /// upload succeeds; a download failure until a download succeeds.
    private(set) var lastErrorMessage: String?
    private(set) var lastFailureClassification: SyncErrorClassifier.Classification?
    /// Set when iCloud refuses Pawtrackr while the account is signed in:
    /// notAuthenticated or permissionFailure, or setup's 134400. That is what
    /// the per-app iCloud switch being off looks like; iCloud Drive being off
    /// (the old ubiquityIdentityToken check) is not.
    private(set) var iCloudAppAccessMayBeDisabled: Bool = false
    private(set) var firstSyncCompleted: Bool
    private(set) var syncEvents: [SyncEvent]
    /// Newest first, capped at 20, persisted apart from the event ring.
    private(set) var failureLog: [SyncFailureRecord]
    private(set) var pendingLocalChangeCount: Int = 0
    private(set) var isAutomaticSyncEnabled: Bool = false
    private(set) var pendingLocalChangeDate: Date?
    private(set) var pendingLocalChangeDescription: String?
    private(set) var offlineBufferedMutationCount: Int = 0
    private(set) var manualCheckRemainingSeconds: Int = 0
    /// CloudKit is moving data right now. Activity only: it never says
    /// anything about health, so it can't hide a failure.
    private(set) var isActivelySyncing: Bool = false
    /// Remote-change notices since launch. Counted instead of logged: each one
    /// used to push a real failure out of the 25-entry event log.
    private(set) var remoteChangeCount: Int = 0
    private(set) var lastRemoteChangeDate: Date?
    /// When the account was last seen become available, this launch.
    private(set) var accountAvailableSince: Date?
    /// A backup from this device replaced the store before it opened. The
    /// first-sync splash ("Restoring your data from iCloud…") would credit
    /// iCloud for clients that came from the device, so RootView skips it;
    /// the first-sync wait itself still runs.
    private(set) var restoredLocalBackupThisLaunch = false

    var canForceSync: Bool {
        manualCheckRemainingSeconds == 0
    }

    /// Container identifier from the entitlements file. Surfaced for the
    /// diagnostics screen so users can read it back to support.
    let containerIdentifier: String = "iCloud.PartnerShipWithMedia.Pawtrackr"

    // MARK: - Private

    private enum ErrorSource: Equatable {
        case upload
        case download
    }

    private enum ActivityHold: Hashable {
        case remoteChange
        case manualCheck
        case remotePush
        case offlineFlush
    }

    /// A failure that has to wait for the account check before it can be
    /// classified (setup's 134400 arrives before CKContainer answers).
    private struct HeldFailure {
        let error: Error
        let kind: SyncEventKind
        let reducerKind: SyncHealthReducer.EventKind?
        let startedAt: Date
        let endedAt: Date
    }

    /// An export or import that never reports its end shouldn't spin forever.
    private static let staleInFlightInterval: TimeInterval = 10 * 60

    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "CloudKit")
    private let container: CKContainer?
    private let networkMonitor = NWPathMonitor()
    private let networkQueue = DispatchQueue(label: "Pawtrackr.CloudKit.Network")
    private var observers: [NSObjectProtocol] = []
    private var hasStarted = false
    private var hasStartedNetworkMonitor = false
    private var modelContainer: ModelContainer?
    private var eventBus: GlobalEventBus?
    private var reducer: SyncHealthReducer
    private var lastErrorSource: ErrorSource?
    /// Bumped when a time-based threshold passes (grace period, one hour of
    /// failures, ten minutes signed in) so views re-read the backup status.
    private var statusRevision = 0
    @ObservationIgnored private var failureReporter: SyncFailureReporting = CompositeSyncFailureReporter([
        TelemetrySyncFailureReporter(),
        // Reads the mode per report: configure(mode:) runs after this exists.
        CloudKitPublicSyncFailureReporter(isEnabled: {
            CloudKitPublicSyncFailureReporter.isEnabled(isMirroring: CloudKitMonitor.shared.mode.isMirroring)
        })
    ])
    @ObservationIgnored private var heldFailures: [HeldFailure] = []
    @ObservationIgnored private var inFlightEvents: [UUID: Date] = [:]
    @ObservationIgnored private var activityHolds: Set<ActivityHold> = []
    @ObservationIgnored private var statusDeadlineTask: Task<Void, Never>?
    @ObservationIgnored private var scheduledStatusDeadline: Date?
    private var remoteWakeWaiters: [UUID: CheckedContinuation<Bool, Never>] = [:]
    private var firstSyncSettleTask: Task<Void, Never>?
    /// Continuations parked by `awaitFirstSyncSettled` (e.g. the onboarding commit),
    /// resumed when the first-sync gate completes or each one's own timeout fires.
    private var firstSyncWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    /// View-independent backstop that flips `firstSyncCompleted` a bounded time
    /// after the account becomes available, so completion no longer depends on
    /// FirstSyncGateView being mounted. Cancelled once first sync completes.
    private var firstSyncLaunchWatchdog: Task<Void, Never>?
    /// The currently-running forceSync watchdog. Replaced (and cancelled) on each
    /// new forceSync call so rapid pull-to-refresh doesn't stack watchdogs.
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
        /// Pre-1.0.3 quota flag. Read once to seed `syncHealth`, then cleared.
        static let quotaExceeded = "cloudkit.quotaExceeded"
        /// `SyncHealthReducer.State` as JSON. Versioned: a later format gets a
        /// new key instead of misreading this one.
        static let syncHealth = "cloudkit.syncHealth.v1"
        static let failureLog = "cloudkit.failureLog.v1"
        /// The upload record of the store a reset or restore set aside, so
        /// support can still tell "never synced" from "uploads rejected".
        /// The other `preReset` keys are copied at the same moment; the next
        /// reset overwrites all of them, which is why each archive's README
        /// carries its own copy.
        static let preResetSyncHealth = "cloudkit.preReset.syncHealth.v1"
        static let preResetCapturedAt = "cloudkit.preReset.capturedAt"
        static let preResetLastExportDate = "cloudkit.preReset.lastExportDate"
        static let preResetLastImportDate = "cloudkit.preReset.lastImportDate"
        static let preResetFirstSyncCompleted = "cloudkit.preReset.firstSyncCompleted"
        static let preResetFallbackActive = "cloudkit.preReset.fallbackActive"
        static let preResetFallbackSince = "cloudkit.preReset.fallbackSince"
        static let preResetSyncEvents = "cloudkit.preReset.syncEvents"
    }

    /// Events kept with a reset's evidence. The 25-entry ring turns over
    /// within minutes of the relaunch that follows.
    nonisolated static let preservedEventCount = 10

    // MARK: - Init

    private init() {
        let defaults = UserDefaults.standard
        self.mode = AppRuntime.allowsICloudSync ? .mirroring : .disabled
        self.container = AppRuntime.allowsICloudSync ? CKContainer(identifier: "iCloud.PartnerShipWithMedia.Pawtrackr") : nil
        self.lastSyncDate = defaults.object(forKey: DefaultsKey.lastSyncDate) as? Date
        self.lastAttemptDate = defaults.object(forKey: DefaultsKey.lastAttemptDate) as? Date
        self.lastImportDate = defaults.object(forKey: DefaultsKey.lastImportDate) as? Date
        self.lastExportDate = defaults.object(forKey: DefaultsKey.lastExportDate) as? Date
        self.firstSyncCompleted = defaults.bool(forKey: DefaultsKey.firstSyncCompleted)
        self.syncEvents = Self.loadPersistedEvents()
        self.failureLog = Self.loadFailureLog(defaults: defaults)
        self.pendingLocalChangeCount = defaults.integer(forKey: DefaultsKey.pendingLocalChangeCount)
        self.pendingLocalChangeDate = defaults.object(forKey: DefaultsKey.pendingLocalChangeDate) as? Date
        self.pendingLocalChangeDescription = defaults.string(forKey: DefaultsKey.pendingLocalChangeDescription)
        self.offlineBufferedMutationCount = OfflineMutationBuffer.count
        // Migrated in memory only: views create this singleton, and a
        // UserDefaults write during view construction has looped the app
        // before. The first real change persists it.
        let health = Self.persistedSyncHealthState(defaults: defaults)
            ?? SyncStatusPolicy.migratedState(from: Self.legacySyncDefaults(defaults: defaults), now: Date())
        self.reducer = SyncHealthReducer(state: health)

        // An upload failure outlives a relaunch, and so must its message.
        if health.exportHealth.isFailing {
            let disposition = health.exportHealth.lastFailureDisposition ?? .unknown
            self.lastErrorMessage = SyncFailureCopy.message(for: disposition, isNetwork: false)
            self.lastErrorSource = .upload
        }
    }

    // MARK: - Lifecycle

    /// Records how this launch opened the store. Call once from
    /// PawtrackrApp.init, before any view mounts and before `start`.
    func configure(mode: Mode, restoredLocalBackup: Bool = false) {
        self.mode = mode
        restoredLocalBackupThisLaunch = restoredLocalBackup
        if !mode.isMirroring {
            isAutomaticSyncEnabled = false
        }
        log.notice("CloudKit mode: \(mode.diagnosticName, privacy: .public)")
        postChange()
    }

    /// Idempotent starter for a mirroring launch. Called once from PawtrackrApp.
    func start(modelContainer: ModelContainer? = nil, eventBus: GlobalEventBus? = nil) {
        guard mode.isMirroring else {
            // A local-only store has no mirroring delegate to watch, and Safe
            // Mode or device metadata would write into a store nothing uploads.
            startStatusObserversOnly()
            return
        }
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
        #if DEBUG
        CloudKitPublicSyncFailureReporter.sendDevelopmentSampleIfRequested(isMirroring: mode.isMirroring)
        #endif
        Task { await refreshAccountStatus() }
    }

    /// Local-only fallback: the account and network rows must still be real
    /// (otherwise Settings says "Checking iCloud…" and "Network unavailable"
    /// forever), but there are no CloudKit events to observe.
    func startStatusObserversOnly() {
        guard !hasStarted else { return }
        hasStarted = true
        observeAccountChanges()
        observeNetworkState()
        Task { await refreshAccountStatus() }
    }

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
            accountAvailableSince = nil
            releaseHeldFailures()
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
            accountAvailableSince = nil
            releaseHeldFailures()
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
            if mapped.isAvailable {
                accountAvailableSince = accountAvailableSince ?? Date()
            } else {
                accountAvailableSince = nil
                // Signed out explains everything; the account banner says so.
                iCloudAppAccessMayBeDisabled = false
            }
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
        releaseHeldFailures()

        // Arm the view-independent first-sync backstop as soon as iCloud is
        // available so onboarding's commit (and the gate) can never wait forever
        // on an empty zone that emits no import event.
        if mapped == .available {
            armFirstSyncLaunchWatchdog()
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
                } else if self.mode.isMirroring, self.accountState.isAvailable {
                    // Heartbeat our device info when we come online
                    self.updateDeviceMetadata()
                    self.flushOfflineMutationBuffer(reason: "Network restored")
                    self.runSafeModeDiagnostics()
                }
                self.postChange()
            }
        }
        networkMonitor.start(queue: networkQueue)
    }

    // MARK: - Device Metadata

    /// Heartbeats the current device's metadata to iCloud.
    /// This allows the business owner to see which worker devices are active.
    func updateDeviceMetadata() {
        guard mode.isMirroring, let modelContainer, accountState.isAvailable, networkState.isOnline else { return }

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
                    
                    Logger.cloudKit.info("Predictive Warming: Media cache prepared for petID=\(pet.uuid.uuidString, privacy: .public) petName=\(pet.name, privacy: .private(mask: .hash))")
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

    /// A remote-change notice says the store changed, not that anything
    /// synced, so it only marks activity and never touches health.
    ///
    /// It must never write to the store. The notice fires for this app's own
    /// saves too, so rebuilding summaries here re-triggered itself every
    /// ~2.4 s: an export stayed queued forever (134417 on every retry) and the
    /// banner sat on "upload pending". Successful `.import` events rebuild.
    private func handlePersistentStoreRemoteChange() {
        remoteChangeCount += 1
        lastRemoteChangeDate = Date()
        hold(.remoteChange)
        modelContainer?.mainContext.processPendingChanges()
        eventBus?.publish(.refreshRequired)
        postChange()

        remoteStoreRefreshTask?.cancel()
        remoteStoreRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, !Task.isCancelled else { return }
            self.modelContainer?.mainContext.processPendingChanges()
            self.release(.remoteChange)
            self.postChange()
        }
    }

    private func handleCloudKitEvent(notification: Notification) {
        guard mode.isMirroring,
              let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event else {
            return
        }

        let kind = syncEventKind(for: event)
        let reducerKind = SyncStatusPolicy.reducerKind(for: event.type)
        guard let endedAt = event.endDate else {
            // In progress: activity only. Writing "syncing" here used to paper
            // over an upload failure until the next event.
            recordSyncAttempt()
            inFlightEvents[event.identifier] = event.startDate
            updateActivity()
            if let reducerKind {
                reducer.apply(.started(reducerKind, at: event.startDate))
            }
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

        inFlightEvents.removeValue(forKey: event.identifier)
        updateActivity()
        if let error = event.error {
            handleError(error, kind: kind, reducerKind: reducerKind, startedAt: event.startDate, endedAt: endedAt)
        } else {
            handleSuccess(kind: kind, reducerKind: reducerKind, startedAt: event.startDate, endedAt: endedAt)
        }
        postChange()
    }

    private func handleSuccess(
        kind: SyncEventKind,
        reducerKind: SyncHealthReducer.EventKind?,
        startedAt: Date,
        endedAt: Date
    ) {
        if let reducerKind {
            reducer.apply(.succeeded(reducerKind, startedAt: startedAt, endedAt: endedAt))
            persistSyncHealth()
        }
        lastSyncDate = endedAt
        UserDefaults.standard.set(lastSyncDate, forKey: DefaultsKey.lastSyncDate)
        appendEvent(
            kind: kind,
            status: .succeeded,
            startedAt: startedAt,
            endedAt: endedAt,
            message: "\(kind.displayLabel) finished",
            errorCode: nil
        )

        switch reducerKind {
        case .export:
            lastExportDate = endedAt
            UserDefaults.standard.set(lastExportDate, forKey: DefaultsKey.lastExportDate)
            // An older success arriving late leaves a newer failure standing.
            if !reducer.state.exportHealth.isFailing {
                if lastErrorSource == .upload {
                    lastErrorMessage = nil
                    lastErrorSource = nil
                    lastFailureClassification = nil
                }
                iCloudAppAccessMayBeDisabled = false
            }
            clearPendingLocalChanges(reason: "CloudKit export finished", coveredUpTo: startedAt)
        case .import:
            lastImportDate = endedAt
            UserDefaults.standard.set(lastImportDate, forKey: DefaultsKey.lastImportDate)
            if lastErrorSource == .download {
                lastErrorMessage = nil
                lastErrorSource = nil
            }
            scheduleFirstSyncCompletionAfterImport()
            rebuildAndReconcileAfterImport()
        case .setup:
            // Mirroring started while signed in, so the per-app switch is on.
            // A setup failure on record still waits for an upload to clear it.
            if accountState.isAvailable {
                iCloudAppAccessMayBeDisabled = false
            }
        case nil:
            break
        }
        resumeRemoteWakeWaiters(success: true)
    }

    private func handleError(
        _ error: Error,
        kind: SyncEventKind,
        reducerKind: SyncHealthReducer.EventKind?,
        startedAt: Date,
        endedAt: Date
    ) {
        if accountState == .unknown, SyncStatusPolicy.needsAccountStatus(error) {
            heldFailures.append(HeldFailure(
                error: error,
                kind: kind,
                reducerKind: reducerKind,
                startedAt: startedAt,
                endedAt: endedAt
            ))
            appendEvent(
                kind: kind,
                status: .waiting,
                startedAt: startedAt,
                endedAt: endedAt,
                message: "Setup failure held until the iCloud account status is known",
                errorCode: "\(NSCocoaErrorDomain).134400"
            )
            return
        }
        let classification = SyncErrorClassifier.classify(error, accountAvailable: accountState.isAvailable)
        recordFailure(classification, kind: kind, reducerKind: reducerKind, startedAt: startedAt, endedAt: endedAt)
    }

    private func releaseHeldFailures() {
        guard accountState != .unknown, !heldFailures.isEmpty else { return }
        let held = heldFailures
        heldFailures.removeAll()
        for failure in held {
            let classification = SyncErrorClassifier.classify(failure.error, accountAvailable: accountState.isAvailable)
            recordFailure(
                classification,
                kind: failure.kind,
                reducerKind: failure.reducerKind,
                startedAt: failure.startedAt,
                endedAt: failure.endedAt
            )
        }
        postChange()
    }

    private func recordFailure(
        _ classification: SyncErrorClassifier.Classification,
        kind: SyncEventKind,
        reducerKind: SyncHealthReducer.EventKind?,
        startedAt: Date,
        endedAt: Date
    ) {
        let disposition = SyncStatusPolicy.failureDisposition(for: classification)
        let code = classification.diagnosticCode
        if let reducerKind {
            reducer.apply(.failed(reducerKind, startedAt: startedAt, endedAt: endedAt, disposition: disposition, code: code))
            persistSyncHealth()
        }

        switch classification.disposition {
        case .userActionable(.notAuthenticated) where reducerKind == .setup:
            // Signed out: mirroring has nothing to set up, and the account
            // banner already says so.
            log.info("CloudKit integration setup skipped: no iCloud account is available.")
            appendEvent(
                kind: kind,
                status: .noted,
                startedAt: startedAt,
                endedAt: endedAt,
                message: "CloudKit setup skipped because no iCloud account is configured",
                errorCode: code
            )
            return
        case .benign:
            // The mirroring delegate resolves record conflicts and retries.
            appendEvent(
                kind: kind,
                status: .noted,
                startedAt: startedAt,
                endedAt: endedAt,
                message: "CloudKit resolved a record conflict and will retry",
                errorCode: code
            )
            return
        default:
            break
        }

        log.error("CloudKit \(kind.rawValue, privacy: .public) failed: \(disposition.rawValue, privacy: .public) \(code, privacy: .public)")
        let message = SyncFailureCopy.message(for: classification)
            ?? SyncFailureCopy.message(for: .unknown, isNetwork: false)
            ?? code
        // An upload failure outranks a download failure, and only an upload
        // clears it, so a failed import mustn't replace its message.
        let uploadFailureStands = lastErrorSource == .upload && reducer.state.exportHealth.isFailing
        if reducerKind != .import || !uploadFailureStands {
            lastErrorMessage = message
            lastErrorSource = reducerKind == .import ? .download : .upload
            lastFailureClassification = classification
        }
        failureLog = SyncStatusPolicy.appending(
            SyncFailureRecord(
                occurredAt: endedAt,
                kind: kind,
                disposition: classification.disposition.diagnosticName,
                code: code,
                serverMessage: classification.serverMessage
            ),
            to: failureLog
        )
        persistFailureLog()

        switch classification.disposition {
        case .userActionable(.accountTemporarilyUnavailable):
            accountState = .temporarilyUnavailable
            accountAvailableSince = nil
            iCloudAppAccessMayBeDisabled = false
        case .userActionable(.notAuthenticated), .setupFailedWhileSignedIn:
            // CKContainer says signed in, but iCloud refuses Pawtrackr: the
            // per-app switch. Re-check in case the account really changed.
            if accountState.isAvailable {
                iCloudAppAccessMayBeDisabled = true
            }
            Task { await refreshAccountStatus() }
        default:
            if accountState.isAvailable,
               classification.innermostDomain == CKError.errorDomain,
               classification.innermostCode == CKError.Code.permissionFailure.rawValue {
                iCloudAppAccessMayBeDisabled = true
            }
        }

        failureReporter.reportIfNeeded(classification)
        appendEvent(
            kind: kind,
            status: .failed,
            startedAt: startedAt,
            endedAt: endedAt,
            message: message,
            errorCode: code
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
        if mode.isMirroring, accountState.isAvailable, pendingLocalChangeCount > 0 {
            hold(.manualCheck)
            startForceSyncWatchdog()
        }
        await refreshAccountStatus()
        postChange()
    }

    func waitForRemoteNotificationSync(timeoutSeconds: Int = 20) async -> Bool {
        recordSyncAttempt()
        hold(.remotePush)
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
                if self.remoteWakeWaiters.isEmpty {
                    self.release(.remotePush)
                    self.postChange()
                }
                continuation.resume(returning: false)
            }
        }
    }

    /// The save sites already show the groomer an error; this only keeps the
    /// failure in diagnostics. It isn't a sync failure, so it must not turn
    /// the iCloud status red or clear a real upload failure's message.
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
        let nsError = error as NSError
        appendEvent(
            kind: .localChange,
            status: .failed,
            message: message,
            errorCode: "\(nsError.domain).\(nsError.code)"
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
        let now = Date()
        // Tracked even while local-only: a later launch that starts mirroring
        // uploads these, and only that upload may cover them.
        reducer.recordLocalChange(at: now)
        persistSyncHealth()
        pendingLocalChangeDescription = operation

        guard mode.isMirroring else {
            // Nothing will upload this launch, so nothing is "waiting for iCloud".
            appendEvent(kind: .localChange, status: .noted, message: operation, errorCode: nil)
            postChange()
            return
        }

        pendingLocalChangeCount += 1
        pendingLocalChangeDate = now
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
        firstSyncLaunchWatchdog?.cancel()
        firstSyncCompleted = true
        UserDefaults.standard.set(true, forKey: DefaultsKey.firstSyncCompleted)
        // Resume anyone awaiting the first-sync gate (e.g. the onboarding commit).
        let waiters = firstSyncWaiters
        firstSyncWaiters.removeAll()
        for waiter in waiters.values { waiter.resume() }
        appendEvent(
            kind: .importFromCloud,
            status: .succeeded,
            message: "Initial iCloud restore gate completed",
            errorCode: nil
        )
        postChange()
    }

    /// Suspends until the first-launch iCloud restore gate has settled (an import
    /// landed, the user skipped, or the launch watchdog fired) or `timeout`
    /// elapses — whichever is first. Returns immediately if already settled.
    /// Onboarding's commit awaits this so a returning user's synced BusinessConfig
    /// is adopted (via fetch-first) rather than duplicated; a genuine new user
    /// waits ~0s because the launch watchdog settles while they fill in the form.
    func awaitFirstSyncSettled(timeout: Duration) async {
        if firstSyncCompleted { return }
        let id = UUID()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            firstSyncWaiters[id] = continuation
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: timeout)
                guard let self, let waiter = self.firstSyncWaiters.removeValue(forKey: id) else { return }
                waiter.resume()
            }
        }
    }

    /// Starts the view-independent first-sync backstop once iCloud is available.
    /// Idempotent: no-ops if first sync already completed or the watchdog is armed.
    private func armFirstSyncLaunchWatchdog() {
        guard !firstSyncCompleted, firstSyncLaunchWatchdog == nil else { return }
        firstSyncLaunchWatchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard let self, !Task.isCancelled else { return }
            self.markFirstSyncCompleted()
        }
    }

    // MARK: - Backup status

    /// What the app may claim about this device's iCloud backup. Everything
    /// the groomer sees about sync health derives from this.
    var backupStatus: BackupStatus {
        _ = statusRevision
        return reducer.backupStatus(conditions: backupConditions, now: Date())
    }

    /// The persisted upload record, for diagnostics and reports.
    var syncHealth: SyncHealthReducer.State {
        reducer.state
    }

    /// True while the reported upload failures are serious enough to show
    /// red: a rejection retrying can't fix, or a streak that isn't a hiccup.
    var isUploadFailureSevere: Bool {
        _ = statusRevision
        guard case .failing = backupStatus else { return false }
        return SyncStatusPolicy.isSevereFailure(reducer.state.exportHealth, isOnline: networkState.isOnline, now: Date())
    }

    /// The red, non-dismissible "iCloud isn't accepting Pawtrackr's data" state.
    var isShowingUploadRejection: Bool {
        _ = statusRevision
        return SyncStatusPolicy.showsUploadRejectionBanner(
            status: backupStatus,
            health: reducer.state.exportHealth,
            isOnline: networkState.isOnline,
            now: Date()
        )
    }

    /// Storage is full and the latest uploads failed because of it. Only a
    /// successful upload clears it; imports and setup can't.
    var quotaExceeded: Bool {
        let health = reducer.state.exportHealth
        return health.isFailing && health.lastFailureDisposition == .quotaExceeded
    }

    /// Local changes have waited past the grace period without an upload.
    var hasUploadsPendingPastGrace: Bool {
        _ = statusRevision
        guard mode.isMirroring, case .notBackedUp(let since?) = backupStatus else { return false }
        return SyncStatusPolicy.isPendingPastGrace(since: since, now: Date())
    }

    /// Derived, never assigned: activity can't overwrite a failure, and a
    /// failure only goes away when its own kind of event succeeds.
    var syncState: SyncState {
        if lastErrorSource == .upload, let lastErrorMessage {
            return .error(message: lastErrorMessage)
        }
        if isActivelySyncing {
            return .syncing
        }
        return .idle
    }

    private var backupConditions: SyncHealthReducer.Conditions {
        SyncHealthReducer.Conditions(
            account: accountState.backupAvailability,
            isOnline: networkState.isOnline,
            isLocalOnly: !mode.isMirroring
        )
    }

    // MARK: - UI helpers

    /// A checkmark only for a confirmed upload.
    var statusIconName: String {
        switch backupStatus {
        case .backedUp: return "checkmark.icloud.fill"
        case .uploading: return "arrow.triangle.2.circlepath.icloud"
        case .failing: return isUploadFailureSevere ? "xmark.icloud.fill" : "exclamationmark.icloud.fill"
        // Neither a checkmark nor an alarm while a first upload is still due.
        case .notBackedUp: return hasUploadsPendingPastGrace ? "exclamationmark.icloud.fill" : "icloud"
        case .signedOut, .localOnly: return "icloud.slash"
        case .unknown: return "icloud"
        }
    }

    var statusTint: SyncStatusTint {
        switch backupStatus {
        case .backedUp: return .success
        case .uploading, .unknown: return .neutral
        case .notBackedUp: return hasUploadsPendingPastGrace ? .warning : .neutral
        case .failing: return isUploadFailureSevere ? .danger : .warning
        case .signedOut: return .warning
        case .localOnly: return mode.isLocalOnlyFallback ? .danger : .neutral
        }
    }

    /// Spoken by VoiceOver on the toolbar icon, so it says what the icon shows.
    var statusAccessibilityLabel: String {
        healthHeadline
    }

    /// Any successful event, imports included. Diagnostics only.
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

    /// End of the newest upload CloudKit accepted, relative, or "Never from
    /// this device". Imported data doesn't count.
    var lastBackupValue: String {
        guard let date = reducer.state.lastSuccessfulExportEndedAt else {
            return AppLocalization.localized("settings.icloud.last_backup_never", value: "Never from this device")
        }
        return Self.relative(date)
    }

    var lastDownloadValue: String {
        guard let date = reducer.state.lastImportEndedAt ?? lastImportDate else {
            return AppLocalization.localized("settings.icloud.last_download_never", value: "Never")
        }
        return Self.relative(date)
    }

    private var lastBackupSummary: String {
        guard let date = reducer.state.lastSuccessfulExportEndedAt else {
            return AppLocalization.localized("cloudkit.last_backup.never", value: "No iCloud backup from this device yet")
        }
        return String(
            format: AppLocalization.localized("cloudkit.last_backup.relative", value: "Last iCloud backup %@"),
            Self.relative(date)
        )
    }

    var pendingChangesSummary: String? {
        guard mode.isMirroring else { return nil }
        let waitingCount = max(pendingLocalChangeCount, offlineBufferedMutationCount)
        guard waitingCount > 0 else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let relative = pendingLocalChangeDate.map { formatter.localizedString(for: $0, relativeTo: Date()) }
        let base = String.localizedStringWithFormat(
            AppLocalization.localized(
                "cloudkit.pending.count",
                value: "%d local change(s) waiting for iCloud"
            ),
            waitingCount
        )
        guard let relative else { return base }
        return "\(base), \(relative)"
    }

    var healthIssues: [SyncHealthIssue] {
        let status = backupStatus
        var issues: [SyncHealthIssue] = []

        switch mode {
        case .disabled:
            return [SyncHealthIssue(
                id: "disabled",
                severity: .info,
                title: AppLocalization.localized("cloudkit.health.disabled.title", value: "iCloud sync is off for this session"),
                detail: AppLocalization.localized("cloudkit.health.disabled.detail", value: "Changes stay on this device.")
            )]
        case .localOnlyFallback:
            issues.append(SyncHealthIssue(
                id: "localOnly",
                severity: .danger,
                title: AppLocalization.localized("cloudkit.banner.local_only.title", value: "iCloud backup is off on this device"),
                detail: AppLocalization.localized(
                    "cloudkit.banner.local_only.message",
                    value: "Pawtrackr couldn't start iCloud sync, so your clients are saved only here."
                )
            ))
        case .mirroring:
            break
        }

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
                detail: SyncFailureCopy.signedOutMessage
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

        if case .failing(_, let disposition) = status, !SyncStatusPolicy.hasDedicatedBanner(disposition) {
            let detail = (lastErrorSource == .upload ? lastErrorMessage : nil)
                ?? SyncFailureCopy.message(for: disposition, isNetwork: false)
                ?? ""
            if isUploadFailureSevere {
                issues.append(SyncHealthIssue(
                    id: "upload.rejected",
                    severity: .danger,
                    title: AppLocalization.localized("cloudkit.banner.rejected.title", value: "iCloud isn't accepting Pawtrackr's data"),
                    detail: detail
                ))
            } else {
                issues.append(SyncHealthIssue(
                    id: "upload.failing",
                    severity: .warning,
                    title: AppLocalization.localized("cloudkit.health.upload_failing.title", value: "Some changes haven't uploaded yet"),
                    detail: detail
                ))
            }
        }

        // Local-only, nothing is trying to upload; the quota record is from
        // an earlier launch and the local-only issue already explains why.
        if quotaExceeded, mode.isMirroring {
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

        if lastErrorSource == .download, let lastErrorMessage {
            issues.append(SyncHealthIssue(
                id: "download.error",
                severity: .warning,
                title: AppLocalization.localized("cloudkit.health.download_error.title", value: "Couldn't download from iCloud"),
                detail: lastErrorMessage
            ))
        }

        if hasUploadsPendingPastGrace, accountState.isAvailable {
            issues.append(SyncHealthIssue(
                id: "pending",
                severity: .warning,
                title: NSLocalizedString("cloudkit.health.pending.title", value: "Changes are waiting to upload", comment: ""),
                detail: pendingChangesSummary ?? AppLocalization.localized(
                    "cloudkit.health.pending.detail_unconfirmed",
                    value: "Changes from this device haven't reached iCloud yet."
                )
            ))
        }

        if mode.isMirroring, accountState.isAvailable, SyncStatusPolicy.showsNeverUploadedWarning(
            state: reducer.state,
            knownClientCount: UserDefaults.standard.integer(forKey: DataSafetyMonitor.lastKnownClientCountKey),
            accountAvailableSince: accountAvailableSince,
            now: Date()
        ) {
            issues.append(SyncHealthIssue(
                id: "neverUploaded",
                severity: .warning,
                title: AppLocalization.localized(
                    "cloudkit.health.never_uploaded.title",
                    value: "Nothing from this device has reached iCloud yet"
                ),
                detail: AppLocalization.localized(
                    "cloudkit.health.never_uploaded.detail",
                    value: "Your clients are saved on this device, but iCloud hasn't confirmed an upload from it. Export your clients before you reset or switch devices."
                )
            ))
        }

        return issues
    }

    var healthHeadline: String {
        let issues = healthIssues
        if let danger = issues.first(where: { $0.severity == .danger }) {
            return danger.title
        }
        if let warning = issues.first(where: { $0.severity == .warning && $0.id != "pending" }) {
            return warning.title
        }
        if hasUploadsPendingPastGrace, let pending = pendingChangesSummary {
            return pending
        }
        switch backupStatus {
        case .backedUp:
            return AppLocalization.localized("cloudkit.health.backed_up", value: "Backed up to iCloud")
        case .uploading:
            return AppLocalization.localized("cloudkit.health.uploading", value: "Uploading to iCloud")
        case .notBackedUp:
            return AppLocalization.localized("cloudkit.health.not_backed_up", value: "Not backed up to iCloud yet")
        case .failing:
            return AppLocalization.localized("cloudkit.health.upload_failing.title", value: "Some changes haven't uploaded yet")
        case .localOnly:
            return issues.first?.title
                ?? AppLocalization.localized("cloudkit.health.disabled.title", value: "iCloud sync is off for this session")
        case .signedOut, .unknown:
            return accountState.displayLabel
        }
    }

    var healthDetail: String {
        let issues = healthIssues
        if let issue = issues.first(where: { $0.severity == .danger }) ?? issues.first(where: { $0.severity == .warning }) {
            return issue.detail
        }
        if hasUploadsPendingPastGrace, let pending = pendingChangesSummary {
            return pending
        }
        if mode == .disabled, let info = issues.first {
            return info.detail
        }
        return "\(lastBackupSummary). \(networkState.displayLabel)"
    }

    enum SyncStatusTint { case success, neutral, warning, danger }

    // MARK: - Private

    private func postChange() {
        scheduleStatusDeadline()
        NotificationCenter.default.post(name: .cloudKitStateDidChange, object: self)
    }

    /// Sleeps until the next time-based threshold instead of polling. Only
    /// rescheduled when that deadline moves.
    private func scheduleStatusDeadline() {
        let next = SyncStatusPolicy.nextStatusDeadline(
            oldestUncoveredLocalChange: reducer.oldestUncoveredLocalChange,
            health: reducer.state.exportHealth,
            accountAvailableSince: accountAvailableSince,
            now: Date()
        )
        guard next != scheduledStatusDeadline else { return }
        statusDeadlineTask?.cancel()
        scheduledStatusDeadline = next
        guard let next else {
            statusDeadlineTask = nil
            return
        }
        let delay = max(0, next.timeIntervalSinceNow) + 1
        statusDeadlineTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled else { return }
            self.scheduledStatusDeadline = nil
            self.statusRevision &+= 1
            self.scheduleStatusDeadline()
        }
    }

    private func hold(_ activity: ActivityHold) {
        activityHolds.insert(activity)
        updateActivity()
    }

    private func release(_ activity: ActivityHold) {
        activityHolds.remove(activity)
        updateActivity()
    }

    private func updateActivity() {
        let cutoff = Date().addingTimeInterval(-Self.staleInFlightInterval)
        inFlightEvents = inFlightEvents.filter { $0.value > cutoff }
        let active = !inFlightEvents.isEmpty || !activityHolds.isEmpty
        if active != isActivelySyncing {
            isActivelySyncing = active
        }
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

        // Routine background sync is silent by design. Import/reconciliation
        // outcomes are recorded in the sync-event log above (visible in
        // CloudKit diagnostics) but must NOT surface a toast — the recurring
        // "Cloud import reconciliation found no issues" banner was flashing on
        // every settled import. Toasts are reserved for explicit user actions
        // and critical errors elsewhere.
    }

    // MARK: - Safe Mode

    /// Flags uploads that have stalled: local changes older than a day while
    /// signed in and online. It can't repair anything (SwiftData exposes no
    /// "upload now"), so it records what it found and re-checks the account;
    /// it never claims a repair.
    func runSafeModeDiagnostics() {
        guard mode.isMirroring, modelContainer != nil, accountState.isAvailable, networkState.isOnline else { return }
        guard let oldest = reducer.oldestUncoveredLocalChange else { return }
        let waiting = Date().timeIntervalSince(oldest)
        guard waiting > SyncStatusPolicy.stalledUploadAge else { return }

        let hours = Int(waiting / 3600)
        Logger.cloudKit.warning("iCloud Safe Mode: local changes have waited \(hours)h for an upload")
        appendEvent(
            kind: .recovery,
            status: .noted,
            message: "iCloud Safe Mode: changes from \(hours)h ago still haven't uploaded. Re-checking the iCloud account.",
            errorCode: reducer.state.exportHealth.lastFailureCode
        )
        postChange()
        Task { await refreshAccountStatus() }
    }

    private func persistEvents() {
        guard let data = try? JSONEncoder().encode(syncEvents) else { return }
        UserDefaults.standard.set(data, forKey: DefaultsKey.syncEvents)
    }

    nonisolated private static func loadPersistedEvents(defaults: UserDefaults = .standard) -> [SyncEvent] {
        guard let data = defaults.data(forKey: DefaultsKey.syncEvents),
              let events = try? JSONDecoder().decode([SyncEvent].self, from: data) else {
            return []
        }
        return Array(events.prefix(25))
    }

    private func persistSyncHealth() {
        guard let data = try? JSONEncoder().encode(reducer.state) else { return }
        UserDefaults.standard.set(data, forKey: DefaultsKey.syncHealth)
        // The reducer carries the quota failure now; the old flag would only
        // re-seed a stale one after a reset.
        UserDefaults.standard.removeObject(forKey: DefaultsKey.quotaExceeded)
    }

    nonisolated static func persistedSyncHealthState(defaults: UserDefaults = .standard) -> SyncHealthReducer.State? {
        guard let data = defaults.data(forKey: DefaultsKey.syncHealth) else { return nil }
        return try? JSONDecoder().decode(SyncHealthReducer.State.self, from: data)
    }

    nonisolated static func legacySyncDefaults(defaults: UserDefaults = .standard) -> SyncStatusPolicy.LegacySyncDefaults {
        SyncStatusPolicy.LegacySyncDefaults(
            lastExportDate: defaults.object(forKey: DefaultsKey.lastExportDate) as? Date,
            lastImportDate: defaults.object(forKey: DefaultsKey.lastImportDate) as? Date,
            lastAttemptDate: defaults.object(forKey: DefaultsKey.lastAttemptDate) as? Date,
            pendingLocalChangeCount: defaults.integer(forKey: DefaultsKey.pendingLocalChangeCount),
            pendingLocalChangeDate: defaults.object(forKey: DefaultsKey.pendingLocalChangeDate) as? Date,
            quotaExceeded: defaults.bool(forKey: DefaultsKey.quotaExceeded)
        )
    }

    private func persistFailureLog() {
        guard let data = try? JSONEncoder().encode(failureLog) else { return }
        UserDefaults.standard.set(data, forKey: DefaultsKey.failureLog)
    }

    nonisolated static func loadFailureLog(defaults: UserDefaults = .standard) -> [SyncFailureRecord] {
        guard let data = defaults.data(forKey: DefaultsKey.failureLog),
              let records = try? JSONDecoder().decode([SyncFailureRecord].self, from: data) else {
            return []
        }
        return Array(records.prefix(SyncStatusPolicy.failureLogLimit))
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

    /// Clears the pending counter only when the export that finished began
    /// after the newest local change: anything saved later rode a later export.
    private func clearPendingLocalChanges(reason: String, coveredUpTo exportStartedAt: Date) {
        guard pendingLocalChangeCount > 0 || offlineBufferedMutationCount > 0 else { return }
        if let newest = pendingLocalChangeDate, newest > exportStartedAt { return }
        pendingLocalChangeCount = 0
        pendingLocalChangeDate = nil
        pendingLocalChangeDescription = nil
        persistPendingLocalChanges()
        OfflineMutationBuffer.clear()
        offlineBufferedMutationCount = 0
        appendEvent(
            kind: .exportToCloud,
            status: .succeeded,
            message: reason,
            errorCode: nil
        )
    }

    /// Drains the display-only offline buffer once iCloud is reachable. It
    /// never touches the pending counter: releasing the buffer uploads
    /// nothing, only an export does.
    private func flushOfflineMutationBuffer(reason: String) {
        guard mode.isMirroring, accountState.isAvailable, networkState.isOnline else { return }
        offlineBufferedMutationCount = OfflineMutationBuffer.count
        guard offlineBufferedMutationCount > 0 else { return }

        offlineFlushTask?.cancel()
        offlineFlushTask = Task { @MainActor [weak self] in
            guard let self else { return }
            self.hold(.offlineFlush)
            defer {
                // A cancelled pass was replaced by a newer one, which owns the hold.
                if !Task.isCancelled {
                    self.release(.offlineFlush)
                    self.postChange()
                }
            }
            while self.accountState.isAvailable, self.networkState.isOnline {
                let batch = OfflineMutationBuffer.peekBatch()
                guard !batch.isEmpty else { break }

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
        release(.remotePush)
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
            guard self.activityHolds.contains(.manualCheck) else { return }
            self.release(.manualCheck)
            self.appendEvent(
                kind: .healthCheck,
                status: .noted,
                message: "No immediate CloudKit event followed the manual check",
                errorCode: nil
            )
            self.postChange()
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

    nonisolated static func isQuotaExceededError(_ error: Error) -> Bool {
        SyncErrorClassifier.classify(error, accountAvailable: true).disposition == .userActionable(.quotaExceeded)
    }

    private static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Reports

    /// The upload record as this build reads it: the persisted state, or the
    /// pre-1.0.3 keys migrated in memory. The recovery screen needs the
    /// fallback most, because a 1.0.1 or 1.0.2 store that won't open may never
    /// have had its record written in the new format.
    nonisolated static func persistedOrMigratedSyncHealth(
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) -> SyncHealthReducer.State {
        persistedSyncHealthState(defaults: defaults)
            ?? SyncStatusPolicy.migratedState(from: legacySyncDefaults(defaults: defaults), now: now)
    }

    /// Upload evidence read straight from UserDefaults, so it works on the
    /// recovery screen where no container (and no live monitor state) exists.
    /// English on purpose: it goes to support. Server messages are sanitized
    /// and truncated; telemetry never carries them.
    nonisolated static func persistedUploadEvidenceLines(defaults: UserDefaults = .standard) -> [String] {
        var lines = uploadRecordLines(for: persistedOrMigratedSyncHealth(defaults: defaults))
        lines.append("First iCloud sync finished: \(defaults.bool(forKey: DefaultsKey.firstSyncCompleted) ? "yes" : "no")")
        lines.append(fallbackLine(
            active: defaults.bool(forKey: AppStoreBootstrap.cloudKitFallbackActiveKey),
            since: defaults.object(forKey: AppStoreBootstrap.cloudKitFallbackSinceKey) as? Date
        ))
        let initError = defaults.string(forKey: AppStoreBootstrap.lastInitErrorKey) ?? "none"
        lines.append("Last init error: \(SupportReportSanitizer.redacted(initError))")
        lines += preResetEvidenceLines(defaults: defaults)

        let failures = loadFailureLog(defaults: defaults)
        lines.append("Recent iCloud failures (\(failures.count)):")
        if failures.isEmpty {
            lines.append("- none")
        } else {
            for failure in failures {
                var line = "- \(failure.occurredAt.formatted()) \(failure.kind.displayLabel) \(failure.disposition) [\(failure.code)]"
                if let message = failure.serverMessage {
                    line += ": " + String(SupportReportSanitizer.redacted(message).prefix(200))
                }
                lines.append(line)
            }
        }
        return lines
    }

    /// The newest persisted sync events, for reports written where the live
    /// monitor isn't running: the recovery screen and archive READMEs.
    nonisolated static func recentSyncEventLines(
        defaults: UserDefaults = .standard,
        limit: Int = preservedEventCount
    ) -> [String] {
        let events = Array(loadPersistedEvents(defaults: defaults).prefix(max(0, limit)))
        return ["Recent sync events (\(events.count)):"] + (events.isEmpty ? ["- none"] : events.map { "- " + eventLine($0) })
    }

    /// Copies what a reset or restore is about to clear into the `preReset`
    /// keys. Without it the evidence of whether this device ever uploaded
    /// leaves with the store, and support can't tell a device that never
    /// synced from one whose uploads iCloud rejected.
    nonisolated static func preserveSyncEvidenceBeforeReset(defaults: UserDefaults = .standard, now: Date = Date()) {
        // The raw bytes when there are some, so fields a newer build added survive.
        if let data = defaults.data(forKey: DefaultsKey.syncHealth) {
            defaults.set(data, forKey: DefaultsKey.preResetSyncHealth)
        } else if let data = try? JSONEncoder().encode(persistedOrMigratedSyncHealth(defaults: defaults, now: now)) {
            defaults.set(data, forKey: DefaultsKey.preResetSyncHealth)
        }
        // Absent values are cleared too, so an older snapshot's leftovers
        // can't pass for part of this one.
        func copy(_ source: String, to destination: String) {
            if let value = defaults.object(forKey: source) {
                defaults.set(value, forKey: destination)
            } else {
                defaults.removeObject(forKey: destination)
            }
        }
        copy(DefaultsKey.lastExportDate, to: DefaultsKey.preResetLastExportDate)
        copy(DefaultsKey.lastImportDate, to: DefaultsKey.preResetLastImportDate)
        copy(DefaultsKey.firstSyncCompleted, to: DefaultsKey.preResetFirstSyncCompleted)
        copy(AppStoreBootstrap.cloudKitFallbackActiveKey, to: DefaultsKey.preResetFallbackActive)
        copy(AppStoreBootstrap.cloudKitFallbackSinceKey, to: DefaultsKey.preResetFallbackSince)
        let events = Array(loadPersistedEvents(defaults: defaults).prefix(preservedEventCount))
        if let data = try? JSONEncoder().encode(events) {
            defaults.set(data, forKey: DefaultsKey.preResetSyncEvents)
        }
        defaults.set(now, forKey: DefaultsKey.preResetCapturedAt)
    }

    /// Single-level "- " lines under each header: SupportService indents
    /// those, and would mangle a deeper level.
    nonisolated private static func uploadRecordLines(for state: SyncHealthReducer.State) -> [String] {
        let health = state.exportHealth
        var lines: [String] = []

        if let ended = state.lastSuccessfulExportEndedAt {
            let started = state.lastSuccessfulExportStartedAt.map { " (started \($0.formatted()))" } ?? ""
            lines.append("Last confirmed iCloud upload from this device: \(ended.formatted())\(started)")
        } else {
            lines.append("Last confirmed iCloud upload from this device: never")
        }
        lines.append("Ever uploaded from this device: \(state.everExportedSuccessfully ? "yes" : "no")")
        if health.isFailing {
            let since = health.firstFailureAt?.formatted() ?? "unknown"
            let cause = health.lastFailureDisposition?.rawValue ?? "unclassified"
            lines.append("Upload health: failing since \(since), \(health.consecutiveFailures) in a row, cause \(cause) [\(health.lastFailureCode ?? "no code")]")
        } else {
            lines.append("Upload health: no failure since the last upload")
        }
        lines.append("Last download: \(state.lastImportEndedAt?.formatted() ?? "never")")
        if let pending = state.firstPendingLocalChangeDate ?? state.pendingLocalChangeDate {
            lines.append("Local changes not yet uploaded since: \(pending.formatted())")
        }
        return lines
    }

    nonisolated private static func preResetEvidenceLines(defaults: UserDefaults) -> [String] {
        guard let data = defaults.data(forKey: DefaultsKey.preResetSyncHealth),
              let previous = try? JSONDecoder().decode(SyncHealthReducer.State.self, from: data) else {
            return []
        }
        // 1.0.3 builds before this change kept only the upload record.
        let captured = (defaults.object(forKey: DefaultsKey.preResetCapturedAt) as? Date)?.formatted() ?? "time not recorded"
        func date(_ key: String) -> String {
            (defaults.object(forKey: key) as? Date)?.formatted() ?? "never"
        }

        var lines = ["Before the last reset or restore (\(captured)):"]
        lines += uploadRecordLines(for: previous).map { "- " + $0 }
        lines.append("- cloudkit.lastExportDate: \(date(DefaultsKey.preResetLastExportDate)), cloudkit.lastImportDate: \(date(DefaultsKey.preResetLastImportDate))")
        lines.append("- First iCloud sync finished: \(defaults.bool(forKey: DefaultsKey.preResetFirstSyncCompleted) ? "yes" : "no")")
        lines.append("- " + fallbackLine(
            active: defaults.bool(forKey: DefaultsKey.preResetFallbackActive),
            since: defaults.object(forKey: DefaultsKey.preResetFallbackSince) as? Date
        ))
        if let eventData = defaults.data(forKey: DefaultsKey.preResetSyncEvents),
           let events = try? JSONDecoder().decode([SyncEvent].self, from: eventData) {
            lines.append("- Sync events kept (\(events.count)):")
            lines += events.map { "- " + eventLine($0) }
        }
        return lines
    }

    nonisolated private static func fallbackLine(active: Bool, since: Date?) -> String {
        guard active else { return "Local-only fallback: no" }
        return "Local-only fallback: yes, since \(since?.formatted() ?? "unknown")"
    }

    nonisolated private static func eventLine(_ event: SyncEvent) -> String {
        let code = event.errorCode.map { " [\($0)]" } ?? ""
        let message = String(SupportReportSanitizer.redacted(event.message).prefix(200))
        return "\(event.startedAt.formatted()) \(event.kind.displayLabel) \(event.status.displayLabel): \(message)\(code)"
    }

    nonisolated static func resetPersistedSyncStateForLocalStoreReset(defaults: UserDefaults = .standard) {
        // The store being set aside takes its upload record with it, but support
        // still needs to see what that record said.
        preserveSyncEvidenceBeforeReset(defaults: defaults)
        defaults.removeObject(forKey: DefaultsKey.syncHealth)
        defaults.removeObject(forKey: DefaultsKey.lastSyncDate)
        defaults.removeObject(forKey: DefaultsKey.lastAttemptDate)
        defaults.removeObject(forKey: DefaultsKey.lastImportDate)
        defaults.removeObject(forKey: DefaultsKey.lastExportDate)
        defaults.removeObject(forKey: DefaultsKey.firstSyncCompleted)
        defaults.removeObject(forKey: DefaultsKey.pendingLocalChangeCount)
        defaults.removeObject(forKey: DefaultsKey.pendingLocalChangeDate)
        defaults.removeObject(forKey: DefaultsKey.pendingLocalChangeDescription)
        defaults.removeObject(forKey: DefaultsKey.quotaExceeded)
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
