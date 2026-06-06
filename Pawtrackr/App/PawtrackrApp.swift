//
//  PawtrackrApp.swift
//  Pawtrackr
//
//  Created by mac on 8/14/25.
//  Updated by Assistant on 2025-09-03
//

import SwiftUI
import SwiftData
import OSLog
import CoreSpotlight
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@main
struct PawtrackrApp: App {
    static let lastInitErrorKey = "pawtrackr.lastInitError"
    /// Set by DataStoreRecoveryView when the user picks "Run Without iCloud".
    /// Honored on the next launch: skips `cloudKitDatabase: .automatic` so a
    /// broken CloudKit schema can't keep the container from initializing.
    static let cloudKitDisabledByRecoveryKey = "pawtrackr.cloudKitDisabledByRecovery"
    /// True when this launch fell back to local-only because CloudKit init
    /// threw. The UI shows a banner so the user knows sync is off.
    static let cloudKitFallbackActiveKey = "pawtrackr.cloudKitFallbackActive"

    let container: ModelContainer?
    private var scheduledTasks: ScheduledTasks?
    let dataStore: DataStoreService?
    let router = NavigationRouter()
    let eventBus = GlobalEventBus()
    @State private var appSettings = AppSettings()
    @State private var authViewModel: AuthenticationViewModel

    // Platform AppDelegate for silent CloudKit pushes.
    #if canImport(UIKit) && !targetEnvironment(macCatalyst)
    @UIApplicationDelegateAdaptor(PawtrackrAppDelegate.self) private var appDelegate
    #elseif canImport(AppKit)
    @NSApplicationDelegateAdaptor(PawtrackrAppDelegate.self) private var appDelegate
    #endif

    init() {
        // 1. Initial local variables for all properties
        var initialContainer: ModelContainer?
        let initialTasks: ScheduledTasks?
        let initialAuthVM: AuthenticationViewModel

        let isUITesting = AppRuntime.isUITesting
        let isRunningUnitTests = AppRuntime.isRunningTests && !isUITesting
        // Unit tests use the Pawtrackr app as their host. If the host opens its
        // own ModelContainer alongside the test's container, the two SwiftData
        // stores coexist in the process and the runtime can invalidate model
        // instances mid-test. Skip container creation entirely for unit tests
        // so the test owns the only container in the process.
        let inMemory = AppRuntime.prefersInMemoryStore
        let logger = Logger(subsystem: "com.pawtrackr", category: "PawtrackrApp")

        if isRunningUnitTests {
            initialContainer = nil
            initialTasks = nil
            initialAuthVM = AuthenticationViewModel(modelContext: nil)
            self.container = nil
            self.scheduledTasks = nil
            self._authViewModel = State(initialValue: initialAuthVM)
            self.dataStore = nil
            return
        }

        // Honor the recovery flag: if a previous launch hit a CloudKit-schema
        // boot loop and the user picked "Run Without iCloud", skip CloudKit
        // on this launch so they can actually open the app.
        let cloudKitDisabledByRecovery = UserDefaults.standard.bool(forKey: PawtrackrApp.cloudKitDisabledByRecoveryKey)
        let wantsCloudKit = !inMemory && !cloudKitDisabledByRecovery && AppRuntime.allowsICloudSync

        let schema = Schema(PawtrackrSchema.models)
        let containerName = inMemory ? "PawtrackrTests" : "Pawtrackr"

        // Try CloudKit first (the normal path). If init throws, retry with
        // .none so the user lands in a working local-only app instead of the
        // recovery screen. A banner elsewhere informs them sync is off.
        var loaded: ModelContainer?
        var fellBackToLocalOnly = false
        var firstError: Error?

        do {
            let primaryConfig = ModelConfiguration(
                containerName,
                schema: schema,
                isStoredInMemoryOnly: inMemory,
                cloudKitDatabase: wantsCloudKit ? .automatic : .none
            )
            loaded = try ModelContainer(for: schema, migrationPlan: PawtrackrMigrationPlan.self, configurations: [primaryConfig])
        } catch {
            firstError = error
            logger.critical("ModelContainer init failed (cloudkit=\(wantsCloudKit)): \(error.localizedDescription, privacy: .public)")

            if wantsCloudKit {
                logger.warning("Falling back to local-only ModelContainer so the user can still open the app.")
                do {
                    let fallbackConfig = ModelConfiguration(
                        containerName,
                        schema: schema,
                        isStoredInMemoryOnly: false,
                        cloudKitDatabase: .none
                    )
                    loaded = try ModelContainer(for: schema, migrationPlan: PawtrackrMigrationPlan.self, configurations: [fallbackConfig])
                    fellBackToLocalOnly = true
                } catch {
                    logger.critical("Local-only fallback also failed: \(error.localizedDescription, privacy: .public)")
                    UserDefaults.standard.set("CloudKit init failed: \(firstError?.localizedDescription ?? "unknown"). Local-only fallback also failed: \(error.localizedDescription)", forKey: PawtrackrApp.lastInitErrorKey)
                }
            } else {
                UserDefaults.standard.set(error.localizedDescription, forKey: PawtrackrApp.lastInitErrorKey)
            }
        }

        if let localContainer = loaded {
            if isUITesting {
                try? UITestDataSeeder.seedIfNeeded(in: localContainer.mainContext)
            }

            initialContainer = localContainer
            initialTasks = inMemory ? nil : ScheduledTasks(modelContainer: localContainer)
            initialAuthVM = AuthenticationViewModel(modelContext: localContainer.mainContext)

            // Validate store health
            if !StoreHealthCheck.isStoreHealthy(container: localContainer) {
                logger.critical("ModelContainer health check failed.")
                UserDefaults.standard.set("Database integrity check failed.", forKey: PawtrackrApp.lastInitErrorKey)
                initialContainer = nil
            } else if fellBackToLocalOnly {
                // Record a non-fatal banner-state for the UI to surface.
                UserDefaults.standard.set(true, forKey: PawtrackrApp.cloudKitFallbackActiveKey)
                UserDefaults.standard.set("CloudKit unavailable: \(firstError?.localizedDescription ?? "unknown error"). Running in local-only mode.", forKey: PawtrackrApp.lastInitErrorKey)
            } else if !cloudKitDisabledByRecovery {
                // Successful CloudKit launch — clear stale fallback markers.
                UserDefaults.standard.removeObject(forKey: PawtrackrApp.cloudKitFallbackActiveKey)
            }
        } else {
            initialContainer = nil
            initialTasks = nil
            initialAuthVM = AuthenticationViewModel(modelContext: nil)
        }

        // 2. Assign all properties
        self.container = initialContainer
        self.scheduledTasks = initialTasks
        self._authViewModel = State(initialValue: initialAuthVM)
        if let container = initialContainer {
            self.dataStore = DataStoreService(container: container)
        } else {
            self.dataStore = nil
        }

        // 3. Start side effects AFTER full initialization
        let cloudKitActive = wantsCloudKit && !fellBackToLocalOnly
        if let localContainer = initialContainer {
            if inMemory {
                Task { @MainActor in
                    CloudKitMonitor.shared.markFirstSyncCompleted()
                }
            } else {
                initialTasks?.start()

                if cloudKitActive {
                    // Start the CloudKit monitor on launch so the UI gets the
                    // earliest possible signal about account/sync state.
                    let busForStart = eventBus
                    Task { @MainActor in
                        CloudKitMonitor.shared.start(modelContainer: localContainer, eventBus: busForStart)
                    }

                    // Register for silent CloudKit pushes.
                    #if canImport(UIKit) && !targetEnvironment(macCatalyst)
                    DispatchQueue.main.async {
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                    #elseif canImport(AppKit)
                    DispatchQueue.main.async {
                        NSApplication.shared.registerForRemoteNotifications()
                    }
                    #endif
                } else {
                    // Local-only mode: tell CloudKitMonitor it's idle so any UI
                    // observing it doesn't show a permanent "syncing…" state.
                    Task { @MainActor in
                        CloudKitMonitor.shared.markFirstSyncCompleted()
                    }
                }

                // Fetch remote configuration
                Task {
                    await RemoteConfigService.shared.fetchConfig()
                }

                #if targetEnvironment(simulator)
                logger.debug("Skipping Bluetooth printer discovery on simulator (unsupported).")
                #else
                Task.detached(priority: .utility) {
                    await BluetoothPeripheralManager.shared.startPrinterDiscovery(autoConnect: true)
                }
                #endif
            }

            // Access UserDefaults directly to avoid using StateObject before it is installed on a view
            let symbol = UserDefaults.standard.string(forKey: "currencySymbol") ?? "$"

            if inMemory {
                Task { @MainActor in
                    Formatters.updateCurrencySymbol(symbol)
                }
            } else {
                Task.detached(priority: .userInitiated) {
                    let ctx = ModelContext(localContainer)
                    await MainActor.run {
                        Formatters.updateCurrencySymbol(symbol)
                    }
                    SummaryUpdater.rebuildAllSummaries(in: ctx)
                }
            }
        }
    }

    var body: some Scene {
        #if os(macOS)
        WindowGroup("Pawtrackr", id: "main") {
            mainWindowContent
        }
        .defaultSize(width: 1220, height: 820)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .newItem) {
                Button(NSLocalizedString("menu_bar.new_client", value: "New Client…", comment: "")) {
                    requestNewClientFromCommand()
                }
                .keyboardShortcut("n", modifiers: .command)

                Button(NSLocalizedString("mac.command.show_insights", value: "Show Insights", comment: "")) {
                    requestNavigationFromCommand(.insights)
                }
                .keyboardShortcut("i", modifiers: .command)

                Button(NSLocalizedString("mac.command.show_clients", value: "Show Clients", comment: "")) {
                    requestNavigationFromCommand(.clients)
                }
                .keyboardShortcut("f", modifiers: .command)
            }
        }
        #else
        WindowGroup {
            mainWindowContent
        }
        #endif

        #if os(macOS)
        Settings {
            if let container = container {
                SettingsView()
                    .environment(appSettings)
                    .environment(authViewModel)
                    .environment(dataStore)
                    .environment(router)
                    .environment(eventBus)
                    .modelContainer(container)
                    .frame(width: 450, height: 500)
            } else {
                Text(NSLocalizedString("common.database_unavailable", value: "Database unavailable", comment: ""))
                    .frame(width: 450, height: 500)
            }
        }

        MenuBarExtra(NSLocalizedString("menu_bar.title", value: "Pawtrackr Pulse", comment: ""), systemImage: "pawprint.circle.fill") {
            if let container = container {
                PawtrackrMenuBarExtra()
                    .environment(dataStore)
                    .modelContainer(container)
            } else {
                Text(NSLocalizedString("common.database_unavailable", value: "Database unavailable", comment: ""))
            }
        }
        .menuBarExtraStyle(.window)
        #endif
    }

    @ViewBuilder
    private var mainWindowContent: some View {
        if let container = container {
            RootView()
                .environment(appSettings)
                .environment(authViewModel)
                .environment(dataStore)
                .environment(router)
                .environment(eventBus)
                .modelContainer(container)
                .onContinueUserActivity("com.pawtrackr.viewPet") { activity in
                    handleViewPetActivity(activity)
                }
                .onContinueUserActivity("com.pawtrackr.viewClient") { activity in
                    handleViewClientActivity(activity)
                }
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    handleSpotlightActivity(activity)
                }
        } else {
            DataStoreRecoveryView()
        }
    }

    // MARK: - Activity Handling

    private func handleViewPetActivity(_ activity: NSUserActivity) {
        guard let petIDString = activity.userInfo?["petID"] as? String,
              let uuid = UUID(uuidString: petIDString) else { return }

        requestNavigation(to: .pet, uuid: uuid)
    }

    private func handleViewClientActivity(_ activity: NSUserActivity) {
        guard let clientIDString = activity.userInfo?["clientID"] as? String,
              let uuid = UUID(uuidString: clientIDString) else { return }

        requestNavigation(to: .client, uuid: uuid)
    }

    private func handleSpotlightActivity(_ activity: NSUserActivity) {
        guard let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return }

        if identifier.hasPrefix("pet-") {
            let uuidString = identifier.replacingOccurrences(of: "pet-", with: "")
            if let uuid = UUID(uuidString: uuidString) {
                requestNavigation(to: .pet, uuid: uuid)
            }
        } else if identifier.hasPrefix("client-") {
            let uuidString = identifier.replacingOccurrences(of: "client-", with: "")
            if let uuid = UUID(uuidString: uuidString) {
                requestNavigation(to: .client, uuid: uuid)
            }
        }
    }

    private func requestNavigation(to kind: PendingNavigationCommand.Kind, uuid: UUID) {
        UserDefaults.standard.set(kind.rawValue, forKey: PendingNavigationCommand.kindKey)
        UserDefaults.standard.set(uuid.uuidString, forKey: PendingNavigationCommand.uuidKey)

        let name: Notification.Name = kind == .pet ? .navigateToPet : .navigateToClient
        NotificationCenter.default.post(name: name, object: nil, userInfo: ["uuid": uuid])
    }

    #if os(macOS)
    private func requestNewClientFromCommand() {
        UserDefaults.standard.set(UUID().uuidString, forKey: AppMenuCommand.pendingNewClientRequestKey)
        NotificationCenter.default.post(name: .showNewClientSheet, object: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func requestNavigationFromCommand(_ item: NavigationItem) {
        NotificationCenter.default.post(name: .selectNavigationItem, object: nil, userInfo: [
            NavigationSelectionKey.item.rawValue: item.rawValue,
            NavigationSelectionKey.resetPath.rawValue: true
        ])
        NSApp.activate(ignoringOtherApps: true)
    }
    #endif
}

extension Notification.Name {
    static let navigateToPet = Notification.Name("navigateToPet")
    static let navigateToClient = Notification.Name("navigateToClient")
}
