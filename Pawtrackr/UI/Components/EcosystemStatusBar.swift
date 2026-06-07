//
//  EcosystemStatusBar.swift
//  Pawtrackr
//
//  Ultra-compact live shop sync indicator for the shared iCloud account.
//

import SwiftUI

struct EcosystemStatusBar: View {
    @State private var monitor = CloudKitMonitor.shared

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
                .scaleEffect(isUpdating ? 1.22 : 1.0)
                .animation(
                    isUpdating ? .easeInOut(duration: 0.45).repeatForever(autoreverses: true) : .default,
                    value: isUpdating
                )

            Text(statusCode)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(.primary)

            if monitor.offlineBufferedMutationCount > 0 {
                Text("\(monitor.offlineBufferedMutationCount)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
                    .accessibilityLabel(Text("\(monitor.offlineBufferedMutationCount) buffered local changes"))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 22)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule().strokeBorder(tint.opacity(0.24), lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private var isUpdating: Bool {
        if case .syncing = monitor.syncState { return true }
        return monitor.offlineBufferedMutationCount > 0
    }

    private var statusCode: String {
        if !monitor.networkState.isOnline {
            return "SHOP_SYNC_OFFLINE"
        }
        if !monitor.accountState.isAvailable {
            return "SHOP_SYNC_WAITING"
        }
        if case .error = monitor.syncState {
            return "SHOP_SYNC_ATTENTION"
        }
        if monitor.pendingChangesSummary != nil {
            return "SHOP_SYNC_PENDING"
        }
        if isUpdating {
            return "SHOP_SYNC_UPDATING"
        }
        return "SHOP_SYNC_LIVE"
    }

    private var tint: Color {
        switch monitor.statusTint {
        case .success:
            return monitor.offlineBufferedMutationCount > 0 ? .orange : .green
        case .neutral:
            return .blue
        case .warning:
            return .orange
        case .danger:
            return .red
        }
    }

    private var accessibilityLabel: String {
        if let pending = monitor.pendingChangesSummary {
            return "\(statusCode), \(pending)"
        }
        if monitor.offlineBufferedMutationCount > 0 {
            return "\(statusCode), \(monitor.offlineBufferedMutationCount) local changes buffered"
        }
        return statusCode
    }
}
