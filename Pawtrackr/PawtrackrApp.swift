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
    @State private var appSettings = AppSettings()
    @StateObject private var authViewModel: AuthenticationViewModel
    private var cancellables: Set<AnyCancellable> = []

    init() {
        // 1. Initial local variables for all properties
        let initialContainer: ModelContainer?
        let initialTasks: ScheduledTasks?
        let initialAuthVM: AuthenticationViewModel

        do {
            let schema = Schema(PawtrackrSchema.models)
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            let localContainer = try ModelContainer(for: schema, migrationPlan: PawtrackrMigrationPlan.self, configurations: [config])
            
            initialContainer = localContainer
            initialTasks = ScheduledTasks(modelContainer: localContainer)
            initialAuthVM = AuthenticationViewModel(modelContext: localContainer.mainContext)
        } catch {
            let logger = Logger(subsystem: "com.pawtrackr", category: "PawtrackrApp")
            logger.critical("Failed to create ModelContainer: \(error.localizedDescription)")
            
            initialContainer = nil
            initialTasks = nil
            
            // Fallback in-memory store
            let schema = Schema(PawtrackrSchema.models)
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            if let dummyContainer = try? ModelContainer(for: schema, configurations: [config]) {
                initialAuthVM = AuthenticationViewModel(modelContext: dummyContainer.mainContext)
            } else {
                fatalError("Failed to initialize even a dummy data store.")
            }
        }

        // 2. Assign all properties
        self.container = initialContainer
        self.scheduledTasks = initialTasks
        self._authViewModel = StateObject(wrappedValue: initialAuthVM)
        
        // 3. Start side effects AFTER full initialization
        if let localContainer = initialContainer {
            initialTasks?.start()
            
            // Access UserDefaults directly to avoid using StateObject before it is installed on a view
            let symbol = UserDefaults.standard.string(forKey: "currencySymbol") ?? "$"
            
            Task.detached(priority: .userInitiated) {
                let ctx = ModelContext(localContainer)
                await MainActor.run { 
                    DataSeeder.seedServicesIfNeeded(in: localContainer.mainContext)
                    Formatters.updateCurrencySymbol(symbol)
                }
                SummaryUpdater.rebuildAllSummaries(in: ctx)
            }

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
        }
    }
    
    var body: some Scene {
        WindowGroup {
            if let container = container {
                if authViewModel.isAuthenticated {
                    ContentView()
                        .environmentObject(appSettings)
                        .environmentObject(authViewModel)
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

        #if os(macOS)
        Settings {
            SettingsView()
                .environmentObject(appSettings)
                .environmentObject(authViewModel)
                .modelContainer(container!) 
                .frame(width: 450, height: 500)
        }
        #endif
    }
}
