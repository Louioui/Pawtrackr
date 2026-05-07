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
    @EnvironmentObject private var authViewModel: AuthenticationViewModel
    @Query private var businessConfigs: [BusinessConfig]
    @State private var cloudKitMonitor = CloudKitMonitor.shared
    @State private var showOnboarding = false
    @State private var didRunStartupMaintenance = false
    @State private var showFirstSyncGate = false

    var body: some View {
        PinLockGate(onUnlock: {
            authViewModel.signInAfterUnlock()
        }) {
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    CloudKitAccountBanner()
                        .animation(.easeInOut(duration: 0.25), value: cloudKitMonitor.accountState)
                    ContentView()
                }
                if showFirstSyncGate {
                    FirstSyncGateView(isPresented: $showFirstSyncGate)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: showFirstSyncGate)
        }
        .adaptiveCover(isPresented: $showOnboarding) {
            OnboardingView {
                showOnboarding = false
            }
            .interactiveDismissDisabled(true)
        }
        .task {
            if !businessConfigs.contains(where: \.isSetupComplete) {
                showOnboarding = true
            }

            // Show the first-sync gate exactly once: when iCloud is signed in
            // and the user has never seen a successful import yet. It auto-times
            // out after 30s so a stuck account never blocks the user.
            updateFirstSyncGate(for: cloudKitMonitor.accountState)

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
        .onChange(of: cloudKitMonitor.accountState) { _, state in
            updateFirstSyncGate(for: state)
        }
        .onChange(of: cloudKitMonitor.firstSyncCompleted) { _, completed in
            if completed {
                showFirstSyncGate = false
            }
        }
    }

    private func updateFirstSyncGate(for accountState: CloudKitMonitor.AccountState) {
        guard accountState.isAvailable, !cloudKitMonitor.firstSyncCompleted else { return }
        showFirstSyncGate = true
    }
}
