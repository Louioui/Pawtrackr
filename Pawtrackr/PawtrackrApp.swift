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

    let container: ModelContainer?
    private var scheduledTasks: ScheduledTasks?
    let dataStore: DataStoreService?
    let router = AppRouter()
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
        let initialContainer: ModelContainer?
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

        do {
            let schema = Schema(PawtrackrSchema.models)
            let config = ModelConfiguration(
                inMemory ? "PawtrackrTests" : "Pawtrackr",
                schema: schema,
                isStoredInMemoryOnly: inMemory,
                cloudKitDatabase: inMemory ? .none : .automatic
            )
            let localContainer = try ModelContainer(for: schema, migrationPlan: PawtrackrMigrationPlan.self, configurations: [config])

            if isUITesting {
                try UITestDataSeeder.seedIfNeeded(in: localContainer.mainContext)
            }

            initialContainer = localContainer
            initialTasks = inMemory ? nil : ScheduledTasks(modelContainer: localContainer)
            initialAuthVM = AuthenticationViewModel(modelContext: localContainer.mainContext)
        } catch {
            // Most common cause: schema changed since the last run and the
            // existing on-disk store doesn't match. We expose this state to
            // the recovery UI (mainWindowContent) which offers the user a
            // "Reset Local Data" button. AuthenticationViewModel now accepts
            // a nil context, so we don't need a dummy container here.
            logger.critical("Failed to create ModelContainer: \(error.localizedDescription, privacy: .public)")
            UserDefaults.standard.set(error.localizedDescription, forKey: PawtrackrApp.lastInitErrorKey)
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
        if let localContainer = initialContainer {
            if inMemory {
                Task { @MainActor in
                    CloudKitMonitor.shared.markFirstSyncCompleted()
                }
            } else {
                initialTasks?.start()

                // Start the CloudKit monitor on launch so the UI gets the
                // earliest possible signal about account/sync state.
                Task { @MainActor in
                    CloudKitMonitor.shared.start()
                }

                // Register for silent CloudKit pushes (used by NSPersistentCloudKitContainer
                // to trigger background fetches when records change on other devices).
                #if canImport(UIKit) && !targetEnvironment(macCatalyst)
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
                #elseif canImport(AppKit)
                DispatchQueue.main.async {
                    NSApplication.shared.registerForRemoteNotifications()
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
        .defaultSize(width: 1200, height: 800)
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
                Text("Database unavailable")
                    .frame(width: 450, height: 500)
            }
        }

        MenuBarExtra("Pawtrackr", systemImage: "pawprint.fill") {
            if let container = container {
                PawtrackrMenuBarExtra()
                    .environment(dataStore)
                    .modelContainer(container)
            } else {
                Text("Database unavailable")
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
}

extension Notification.Name {
    static let navigateToPet = Notification.Name("navigateToPet")
    static let navigateToClient = Notification.Name("navigateToClient")
}
