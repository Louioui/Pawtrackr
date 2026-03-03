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

@main
struct PawtrackrApp: App {
    let container: ModelContainer?
    private var scheduledTasks: ScheduledTasks?
    @StateObject private var appSettings = AppSettings()
    @StateObject private var authViewModel: AuthenticationViewModel
    private var cancellables: Set<AnyCancellable> = []

    init() {
        do {
            let schema = Schema(PawtrackrSchema.models)
            // Use a plain local store by default. CloudKit requires entitlements and will crash on launch if unavailable.
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            
            // Create the container first as a local constant.
            let localContainer = try ModelContainer(for: schema, migrationPlan: PawtrackrMigrationPlan.self, configurations: [config])
            
            // Now create the task, capturing only the local constant.
            Task { @MainActor in
                DataSeeder.seedServicesIfNeeded(in: localContainer.mainContext)
                // Rebuild all historical summaries to ensure revenue data is captured
                SummaryUpdater.rebuildAllSummaries(in: localContainer.mainContext)
            }

            // Finally, assign the container to the instance property.
            self.container = localContainer
            self.scheduledTasks = ScheduledTasks(modelContainer: localContainer)
            self.scheduledTasks?.start()

            _authViewModel = StateObject(wrappedValue: AuthenticationViewModel(modelContext: localContainer.mainContext))

            // Add a subscriber to automatically update day summaries when a visit completes.
            // Use a background context so checkout UI is never blocked by aggregation work.
            NotificationCenter.default.publisher(for: .visitDidComplete)
                .sink { notification in
                    guard let date = notification.endedAtDate else { return }
                    let targetDate = date
                    Task.detached(priority: .utility) {
                        let backgroundContext = ModelContext(localContainer)
                        SummaryUpdater.rebuildDay(for: targetDate, in: backgroundContext)
                    }
                }
                .store(in: &cancellables)
            
        } catch {
            let logger = Logger(subsystem: "com.pawtrackr", category: "PawtrackrApp")
            logger.critical("Failed to create ModelContainer: \(error.localizedDescription)")
            self.container = nil
            self.scheduledTasks = nil
            // Initialize authViewModel even in failure case to avoid crashes, but it won't be fully functional.
            // A dummy or error-state context could be used if available.
            // For now, creating it with a throwaway in-memory store.
            do {
                let schema = Schema(PawtrackrSchema.models)
                let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                let dummyContainer = try ModelContainer(for: schema, configurations: [config])
                _authViewModel = StateObject(wrappedValue: AuthenticationViewModel(modelContext: dummyContainer.mainContext))
            } catch {
                // If even the in-memory container fails, something is fundamentally wrong.
                // We'll have to leave authViewModel uninitialized in this very unlikely edge case,
                // which the view will handle.
                fatalError("Failed to create even a dummy ModelContainer: \(error)")
            }
        }
    }
    
    var body: some Scene {
        WindowGroup {
            if let container = container {
                if authViewModel.isAuthenticated {
                    ContentView()
                        .environmentObject(appSettings)
                        .environmentObject(authViewModel)
                        // Inject the shared SwiftData container so all views read/write the same store.
                        .modelContainer(container)
                } else {
                    LoginView()
                        .environmentObject(appSettings)
                        .environmentObject(authViewModel)
                        .modelContainer(container)
                }
            } else {
                VStack {
                    Text("Failed to initialize the app's data store.")
                        .font(.headline)
                        .padding()
                    Text("Please try restarting the app. If the problem persists, contact support.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding()
                }
            }
        }
        #if os(macOS)
        .defaultSize(width: 1200, height: 800)
        #endif
    }
}
