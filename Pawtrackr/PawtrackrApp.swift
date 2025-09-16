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

@main
struct PawtrackrApp: App {
    let container: ModelContainer
    private let scheduledTasks: ScheduledTasks
    
    init() {
        do {
            let schema = Schema(PawtrackrSchema.models)
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .automatic)
            
            // Create the container first as a local constant.
            let localContainer = try ModelContainer(for: schema, configurations: [config], migrationPlan: PawtrackrMigrationPlan.self)
            
            // Now create the task, capturing only the local constant.
            Task { @MainActor in
                DataMigrations.seedServicesIfNeeded(in: localContainer.mainContext)
            }
            
            // Finally, assign the container to the instance property.
            self.container = localContainer
            self.scheduledTasks = ScheduledTasks(modelContainer: localContainer)
            self.scheduledTasks.start()
            
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
    
    @StateObject private var appSettings = AppSettings()
    @StateObject private var authViewModel: AuthenticationViewModel

    init() {
        do {
            let schema = Schema(PawtrackrSchema.models)
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .automatic)
            
            // Create the container first as a local constant.
            let localContainer = try ModelContainer(for: schema, configurations: [config], migrationPlan: PawtrackrMigrationPlan.self)
            
            // Now create the task, capturing only the local constant.
            Task { @MainActor in
                DataMigrations.seedServicesIfNeeded(in: localContainer.mainContext)
            }
            
            // Finally, assign the container to the instance property.
            self.container = localContainer
            self.scheduledTasks = ScheduledTasks(modelContainer: localContainer)
            self.scheduledTasks.start()

            _authViewModel = StateObject(wrappedValue: AuthenticationViewModel(modelContext: localContainer.mainContext))
            
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            if authViewModel.isAuthenticated {
                CoordinatorView()
                    .environmentObject(appSettings)
                    .environmentObject(authViewModel)
            } else {
                LoginView()
                    .environmentObject(authViewModel)
            }
        }
    }
}
