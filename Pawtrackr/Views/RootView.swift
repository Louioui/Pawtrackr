//
//  RootView.swift
//  Pawtrackr
//
//  App shell: PIN gate + main tabs
//

import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        PinLockGate {
            MainTabView()
        }
        .task {
            DataMigrations.coercePets(in: modelContext)
            DataMigrations.seedServicesIfNeeded(in: modelContext)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                TimeHub.shared.resume()
            case .inactive, .background:
                TimeHub.shared.pause()
            @unknown default:
                break
            }
        }
    }
}
