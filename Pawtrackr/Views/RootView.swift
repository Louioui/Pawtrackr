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
    @Query private var businessConfigs: [BusinessConfig]
    @State private var showOnboarding = false

    var body: some View {
        PinLockGate {
            MainTabView()
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView {
                showOnboarding = false
            }
        }
        .task {
            if businessConfigs.isEmpty || !businessConfigs[0].isSetupComplete {
                showOnboarding = true
            }
            
            DataMigrations.coercePets(in: modelContext)
            DataMigrations.ensureServiceCatalog(in: modelContext)
            DataMigrations.ensureMessageTemplates(in: modelContext)

            DataMigrations.backfillDaySummaries(in: modelContext)
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
