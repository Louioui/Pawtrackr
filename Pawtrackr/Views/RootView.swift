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
    @State private var didRunStartupMaintenance = false

    var body: some View {
        PinLockGate {
            MainTabView()
        }
        .adaptiveCover(isPresented: $showOnboarding) {
            OnboardingView {
                showOnboarding = false
            }
        }
        .task {
            if businessConfigs.isEmpty || !businessConfigs[0].isSetupComplete {
                showOnboarding = true
            }

            guard !didRunStartupMaintenance else { return }
            didRunStartupMaintenance = true

            let container = modelContext.container
            Task.detached(priority: .utility) {
                let backgroundContext = ModelContext(container)
                DataMigrations.coercePets(in: backgroundContext)
                DataMigrations.ensureServiceCatalog(in: backgroundContext)
                DataMigrations.ensureMessageTemplates(in: backgroundContext)
                DataMigrations.backfillDaySummaries(in: backgroundContext)
            }
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
