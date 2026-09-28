//
//  CloudKitStatusView.swift
//  Pawtrackr
//
//  Compact iCloud sync status indicator for the toolbar / sidebar.
//
//  Icon and tint come from CloudKitMonitor.backupStatus, which is built
//  from uploads alone:
//  - checkmark.icloud.fill (green) — only when an upload CloudKit accepted
//    covers this device's changes. Imports never earn it.
//  - arrow.triangle.2.circlepath.icloud (spinning) — an upload is carrying
//    changes that aren't covered yet
//  - exclamationmark.icloud.fill (orange) — changes waiting past the grace
//    period, or upload failures that may still clear
//  - xmark.icloud.fill (red) — iCloud keeps rejecting uploads
//  - icloud.slash — signed out, or local-only (red)
//
//  Tap reveals a small popover with the backup status and a "Check iCloud" button.
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

    /// Only the upload icon spins; a spinning checkmark during imports would
    /// suggest an upload that isn't happening.
    private var isSpinning: Bool {
        monitor.backupStatus == .uploading
    }

    private var tintColor: Color {
        switch monitor.statusTint {
        case .success: return .green
        case .neutral: return .secondary
        case .warning: return .orange
        case .danger: return .red
        }
    }

    /// Says what the icon shows: VoiceOver used to announce "Synced with
    /// iCloud" next to a warning icon.
    private var accessibilityLabel: String {
        monitor.statusAccessibilityLabel
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
                    Label(pending, systemImage: "icloud.and.arrow.up")
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
                Label(manualCheckTitle,
                      systemImage: monitor.canForceSync ? "arrow.clockwise.icloud" : "timer")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(!monitor.canForceSync)
        }
        .padding(14)
    }

    private var manualCheckTitle: String {
        monitor.manualCheckAvailability.buttonTitle
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
