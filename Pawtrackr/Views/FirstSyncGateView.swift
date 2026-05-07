//
//  FirstSyncGateView.swift
//  Pawtrackr
//
//  Splash overlay shown only on the very first launch with an iCloud account.
//  It waits for the initial CloudKit import (so the user doesn't accidentally
//  duplicate clients that are about to come down from iCloud) and times out
//  after 30 seconds so a stuck account never blocks the app forever.
//

import SwiftUI

struct FirstSyncGateView: View {
    @Binding var isPresented: Bool
    @State private var monitor = CloudKitMonitor.shared
    @State private var elapsedSeconds: Int = 0
    @State private var watchdog: Task<Void, Never>?

    private let timeoutSeconds: Int = 30

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "icloud.and.arrow.down")
                    .font(.system(size: 48))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
                Text(NSLocalizedString("cloudkit.first_sync.title", value: "Restoring your data from iCloud…", comment: ""))
                    .font(.headline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text(NSLocalizedString("cloudkit.first_sync.subtitle", value: "This only happens once.", comment: ""))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                ProgressView(value: Double(elapsedSeconds), total: Double(timeoutSeconds))
                    .progressViewStyle(.linear)
                    .tint(.white)
                    .frame(maxWidth: 240)
                Button {
                    finish()
                } label: {
                    Text(NSLocalizedString("cloudkit.first_sync.skip", value: "Skip", comment: ""))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding(.top, 4)
            }
            .padding(28)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(40)
        }
        .onAppear { startWatchdog() }
        .onDisappear { watchdog?.cancel() }
        .onChange(of: monitor.firstSyncCompleted) { _, done in
            if done { finish() }
        }
    }

    private func startWatchdog() {
        watchdog?.cancel()
        elapsedSeconds = 0
        watchdog = Task { @MainActor in
            for _ in 0..<timeoutSeconds {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                elapsedSeconds += 1
                if monitor.firstSyncCompleted { finish(); return }
            }
            finish()
        }
    }

    private func finish() {
        watchdog?.cancel()
        monitor.markFirstSyncCompleted()
        withAnimation(.easeOut(duration: 0.25)) {
            isPresented = false
        }
    }
}
