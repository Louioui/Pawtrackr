//
//  CloudKitStatusView.swift
//  Pawtrackr
//
//  Compact iCloud sync status indicator for the toolbar / sidebar.
//
//  Visual states:
//  - 🟢 checkmark.icloud.fill        — synced
//  - 🟡 exclamationmark.icloud.fill  — signed out / quota exceeded
//  - 🔴 xmark.icloud.fill            — sync error
//  - ⏳ arrow.triangle.2.circlepath.icloud (spinning) — syncing
//
//  Tap reveals a small popover with last-sync time and a "Sync Now" button.
//

import SwiftUI

struct CloudKitStatusView: View {
    @State private var monitor = CloudKitMonitor.shared
    @State private var showingPopover = false
    @State private var spin = false

    var body: some View {
        Button {
            showingPopover.toggle()
        } label: {
            Image(systemName: monitor.statusIconName)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tintColor)
                .rotationEffect(.degrees(isSpinning ? 360 : 0))
                .animation(
                    isSpinning
                        ? .linear(duration: 1.2).repeatForever(autoreverses: false)
                        : .default,
                    value: isSpinning
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .popover(isPresented: $showingPopover, arrowEdge: .bottom) {
            CloudKitStatusPopover(monitor: monitor)
                .frame(minWidth: 260, idealWidth: 280)
        }
    }

    private var isSpinning: Bool {
        if case .syncing = monitor.syncState { return true }
        return false
    }

    private var tintColor: Color {
        switch monitor.statusTint {
        case .success: return .green
        case .neutral: return .secondary
        case .warning: return .orange
        case .danger: return .red
        }
    }

    private var accessibilityLabel: String {
        switch monitor.syncState {
        case .syncing: return NSLocalizedString("cloudkit.status.syncing", value: "Syncing with iCloud", comment: "")
        case .error(let message): return message
        case .idle:
            if monitor.accountState.isAvailable {
                return NSLocalizedString("cloudkit.status.synced", value: "Synced with iCloud", comment: "")
            }
            return monitor.accountState.displayLabel
        }
    }
}

// MARK: - Popover

private struct CloudKitStatusPopover: View {
    let monitor: CloudKitMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: monitor.statusIconName)
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline).font(.headline)
                    Text(monitor.lastSyncSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if let message = monitor.lastErrorMessage, case .error = monitor.syncState {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Button {
                Task { await monitor.forceSync() }
            } label: {
                Label(NSLocalizedString("cloudkit.action.sync_now", value: "Sync Now", comment: ""),
                      systemImage: "arrow.clockwise.icloud")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled({
                if case .syncing = monitor.syncState { return true }
                return false
            }())
        }
        .padding(14)
    }

    private var tint: Color {
        switch monitor.statusTint {
        case .success: return .green
        case .neutral: return .secondary
        case .warning: return .orange
        case .danger: return .red
        }
    }

    private var headline: String {
        if !monitor.accountState.isAvailable {
            return monitor.accountState.displayLabel
        }
        if monitor.quotaExceeded {
            return NSLocalizedString("cloudkit.status.quota_exceeded", value: "iCloud Storage Full", comment: "")
        }
        switch monitor.syncState {
        case .idle: return NSLocalizedString("cloudkit.status.up_to_date", value: "Up to date", comment: "")
        case .syncing: return NSLocalizedString("cloudkit.status.syncing", value: "Syncing…", comment: "")
        case .error: return NSLocalizedString("cloudkit.status.error", value: "Sync error", comment: "")
        }
    }
}
