//
//  ActivityFeedView.swift
//  Pawtrackr
//
//  Live stream of salon activity and iCloud sync events.
//

import SwiftUI
import SwiftData

struct ActivityFeedView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var monitor = CloudKitMonitor.shared
    @Query(sort: \DeviceMetadata.lastSyncAt, order: .reverse) private var devices: [DeviceMetadata]
    
    var body: some View {
        NavigationStack {
            List {
                Section(AppLocalization.localized("dashboard.activity.section", value: "Recent Activity")) {
                    if monitor.syncEvents.isEmpty {
                        ContentUnavailableView(
                            AppLocalization.localized("dashboard.activity.empty_title", value: "No Recent Activity"),
                            systemImage: "clock.arrow.2.circlepath",
                            description: Text(AppLocalization.localized("dashboard.activity.empty_detail", value: "Worker actions and sync events will appear here."))
                        )
                    } else {
                        ForEach(monitor.syncEvents) { event in
                            ActivityRow(event: event, devices: devices)
                        }
                    }
                }
            }
            .navigationTitle(AppLocalization.localized("dashboard.activity.title", value: "Salon Activity"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.localized("common.done", value: "Done")) { dismiss() }
                }
            }
        }
    }
}

struct ActivityRow: View {
    let event: CloudKitMonitor.SyncEvent
    let devices: [DeviceMetadata]
    
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(tint.opacity(0.15))
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tint)
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(event.message)
                    .font(.subheadline.weight(.medium))
                
                HStack(spacing: 4) {
                    Text(deviceName)
                    Text("•")
                    Text(event.startedAt.formatted(.relative(presentation: .numeric)))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if event.status == .failed {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
    
    private var deviceName: String {
        devices.first { $0.deviceID == event.deviceID }?.name ?? AppLocalization.localized("common.unknown_device", value: "Unknown Device")
    }
    
    private var icon: String {
        switch event.kind {
        case .importFromCloud: return "icloud.and.arrow.down.fill"
        case .exportToCloud: return "icloud.and.arrow.up.fill"
        case .localChange: return "pencil.circle.fill"
        case .remotePush: return "bell.fill"
        case .account: return "person.crop.circle.fill"
        case .media: return "photo.fill"
        case .setup: return "gearshape.fill"
        default: return "arrow.triangle.2.circlepath"
        }
    }
    
    private var tint: Color {
        switch event.status {
        case .failed: return .red
        case .succeeded: return .green
        case .started: return .blue
        case .waiting: return .orange
        case .noted: return .secondary
        }
    }
}
