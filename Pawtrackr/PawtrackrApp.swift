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
import Combine
import CoreSpotlight
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// Holds Combine subscriptions that must outlive the App struct's value copies.
private final class AppCancellables {
    var bag: Set<AnyCancellable> = []
}

@main
struct PawtrackrApp: App {
    static let lastInitErrorKey = "pawtrackr.lastInitError"

    let container: ModelContainer?
    private var scheduledTasks: ScheduledTasks?
    @State private var appSettings = AppSettings()
    @StateObject private var authViewModel: AuthenticationViewModel
    // Using a class wrapper so subscriptions survive struct copies.
    private let cancellables = AppCancellables()

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

        let logger = Logger(subsystem: "com.pawtrackr", category: "PawtrackrApp")
        do {
            let schema = Schema(PawtrackrSchema.models)
            let config = ModelConfiguration(
                "Pawtrackr",
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .automatic
            )
            let localContainer = try ModelContainer(for: schema, migrationPlan: PawtrackrMigrationPlan.self, configurations: [config])

            initialContainer = localContainer
            initialTasks = ScheduledTasks(modelContainer: localContainer)
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
        self._authViewModel = StateObject(wrappedValue: initialAuthVM)

        // 3. Start side effects AFTER full initialization
        if let localContainer = initialContainer {
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

            // Access UserDefaults directly to avoid using StateObject before it is installed on a view
            let symbol = UserDefaults.standard.string(forKey: "currencySymbol") ?? "$"

            Task.detached(priority: .userInitiated) {
                let ctx = ModelContext(localContainer)
                await MainActor.run {
                    Formatters.updateCurrencySymbol(symbol)
                }
                SummaryUpdater.rebuildAllSummaries(in: ctx)
            }

            NotificationCenter.default.publisher(for: .visitDidComplete)
                .receive(on: RunLoop.main)
                .sink { notification in
                    guard let date = notification.endedAtDate else { return }
                    let targetDate = date

                    // Detach and use a background context for heavy work
                    Task.detached(priority: .utility) {
                        let backgroundContext = ModelContext(localContainer)
                        SummaryUpdater.rebuildDay(for: targetDate, in: backgroundContext)
                    }
                }
                .store(in: &cancellables.bag)
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
                    .environmentObject(appSettings)
                    .environmentObject(authViewModel)
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
                .environmentObject(appSettings)
                .environmentObject(authViewModel)
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
