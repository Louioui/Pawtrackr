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
    @Environment(AuthenticationViewModel.self) private var authViewModel
    @Query private var businessConfigs: [BusinessConfig]
    @State private var cloudKitMonitor = CloudKitMonitor.shared
    @State private var showOnboarding = false
    @State private var didEvaluateOnboarding = false
    @State private var didRunStartupMaintenance = false
    @State private var showFirstSyncGate = false
    @State private var bypassLockForCurrentSession = false
    @State private var showPrivacyScreen = false
    @State private var showWhatIsNew = false

    var body: some View {
        ZStack {
            Group {
                if shouldBypassLockGate {
                    mainShell
                } else {
                    PinLockGate(onUnlock: {
                        authViewModel.signInAfterUnlock()
                    }) {
                        mainShell
                    }
                }
            }
            
            if showPrivacyScreen {
                PrivacyScreen()
                    .transition(.opacity)
                    .zIndex(100)
            }
        }
        .sheet(isPresented: $showWhatIsNew) {
            WhatIsNewView {
                showWhatIsNew = false
                UserDefaults.standard.set(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String, forKey: "lastSeenVersion")
            }
        }
        .adaptiveCover(isPresented: $showOnboarding) {
            OnboardingView {
                showOnboarding = false
                bypassLockForCurrentSession = true
                authViewModel.signInAfterUnlock()
            }
            .interactiveDismissDisabled(true)
        }
        .task {
            evaluateWhatIsNew()
            // Show the first-sync gate exactly once: when iCloud is signed in
            // and the user has never seen a successful import yet. It auto-times
            // out after 30s so a stuck account never blocks the user.
            updateFirstSyncGate(for: cloudKitMonitor.accountState)
            evaluateOnboardingIfReady()
            runStartupMaintenanceIfReady()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                TimeHub.shared.resume()
                withAnimation {
                    showPrivacyScreen = false
                }
            case .inactive:
                // On iPad, inactive can mean the app is still visible (multitasking).
                // Do not show the privacy screen yet.
                break
            case .background:
                TimeHub.shared.pause()
                bypassLockForCurrentSession = false
                withAnimation {
                    showPrivacyScreen = true
                }
            @unknown default:
                break
            }
        }
        .onChange(of: cloudKitMonitor.accountState) { _, state in
            updateFirstSyncGate(for: state)
            evaluateOnboardingIfReady()
            runStartupMaintenanceIfReady()
        }
        .onChange(of: cloudKitMonitor.firstSyncCompleted) { _, completed in
            if completed {
                showFirstSyncGate = false
            }
            evaluateOnboardingIfReady()
            runStartupMaintenanceIfReady()
        }
    }

    private var mainShell: some View {
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

    private func updateFirstSyncGate(for accountState: CloudKitMonitor.AccountState) {
        guard accountState.isAvailable, !cloudKitMonitor.firstSyncCompleted else { return }
        showFirstSyncGate = true
    }

    private func evaluateWhatIsNew() {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let lastSeenVersion = UserDefaults.standard.string(forKey: "lastSeenVersion")
        if currentVersion != lastSeenVersion {
            showWhatIsNew = true
        }
    }

    private var canProceedPastFirstSync: Bool {
        if cloudKitMonitor.firstSyncCompleted { return true }
        switch cloudKitMonitor.accountState {
        case .unknown:
            return false
        case .available:
            return false
        case .noAccount, .restricted, .temporarilyUnavailable, .couldNotDetermine:
            return true
        }
    }

    private func evaluateOnboardingIfReady() {
        guard canProceedPastFirstSync, !didEvaluateOnboarding else { return }
        didEvaluateOnboarding = true
        if !businessConfigs.contains(where: \.isSetupComplete) {
            showOnboarding = true
        }
    }

    private func runStartupMaintenanceIfReady() {
        guard canProceedPastFirstSync, !didRunStartupMaintenance else { return }
        didRunStartupMaintenance = true
        guard !AppRuntime.isUITesting else { return }

        let container = modelContext.container
        Task.detached(priority: .utility) {
            let backgroundContext = ModelContext(container)
            DataMigrations.coercePets(in: backgroundContext)
            DataMigrations.ensureServiceCatalog(in: backgroundContext)
            DataMigrations.ensureMessageTemplates(in: backgroundContext)
            SummaryUpdater.rebuildAllSummaries(in: backgroundContext)
        }
    }

    private var onboardingIncomplete: Bool {
        !businessConfigs.contains(where: \.isSetupComplete)
    }

    private var shouldBypassLockGate: Bool {
        onboardingIncomplete || showOnboarding || bypassLockForCurrentSession
    }
}
