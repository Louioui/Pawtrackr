//
//  PawtrackrApp.swift
//  Pawtrackr
//
//  Created by mac on 8/14/25.
//

import SwiftUI
import SwiftData

@main
struct PawtrackrApp: App {
    // Single shared SwiftData container for the app
    let modelContainer: ModelContainer

    init() {
        // Register all models used by the app
        let schema = Schema([
            Client.self,
            Pet.self,
            Visit.self,
            VisitItem.self,
            Service.self,
            Payment.self
        ])

        // Default on-device storage; change configuration as needed
        let config = ModelConfiguration()

        do {
            modelContainer = try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("Failed to create SwiftData container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            // Entry point: Client Center (no bottom tabs by design)
            ClientsView()
        }
        .modelContainer(modelContainer)
    }
}
