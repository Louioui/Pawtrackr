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
    var body: some View {
        PinLockGate {
            MainTabView()
        }
        .task {
            DataMigrations.coercePets(in: modelContext)
            DataMigrations.seedServicesIfNeeded(in: modelContext)
        }
    }
}
