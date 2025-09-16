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
    
    init() {
        do {
            let schema = Schema(PawtrackrSchema.models)
            
            // Create the container first as a local constant.
            let localContainer = try ModelContainer(for: schema, migrationPlan: PawtrackrMigrationPlan.self)
            
            // Now create the task, capturing only the local constant.
            Task { @MainActor in
                DataMigrations.seedServicesIfNeeded(in: localContainer.mainContext)
            }
            
            // Finally, assign the container to the instance property.
            self.container = localContainer
            
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
    
    @StateObject private var appSettings = AppSettings()
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appSettings)
        }
    }
}
