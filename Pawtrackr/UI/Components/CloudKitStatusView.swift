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
                    Text(monitor.healthHeadline).font(.headline)
                    Text(monitor.healthDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                Label(monitor.networkState.displayLabel, systemImage: monitor.networkState.isOnline ? "wifi" : "wifi.slash")
                Spacer(minLength: 8)
                if let pending = monitor.pendingChangesSummary {
                    Label(pending, systemImage: "arrow.up.icloud")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            if let message = monitor.lastErrorMessage, case .error = monitor.syncState {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if !monitor.healthIssues.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(monitor.healthIssues.prefix(3)) { issue in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: iconName(for: issue.severity))
                                .foregroundStyle(tint(for: issue.severity))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(issue.title).font(.caption.weight(.semibold))
                                Text(issue.detail).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(8)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Button {
                Task { await monitor.forceSync() }
            } label: {
                Label(NSLocalizedString("cloudkit.action.check_status", value: "Check iCloud", comment: ""),
                      systemImage: "arrow.clockwise.icloud")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(true) // Disabled per user request
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

    private func iconName(for severity: CloudKitMonitor.SyncHealthIssue.Severity) -> String {
        switch severity {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle.fill"
        case .danger: return "xmark.octagon.fill"
        }
    }

    private func tint(for severity: CloudKitMonitor.SyncHealthIssue.Severity) -> Color {
        switch severity {
        case .info: return .blue
        case .warning: return .orange
        case .danger: return .red
        }
    }
}
