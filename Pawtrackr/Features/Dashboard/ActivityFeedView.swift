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
    @State private var isChecking = false
    @Query(sort: \DeviceMetadata.lastSyncAt, order: .reverse) private var devices: [DeviceMetadata]
    @Query(sort: \PresenceRecord.updatedAt, order: .reverse) private var presenceRecords: [PresenceRecord]

    private let freshnessWindow: TimeInterval = 600
    private let recentWindow: TimeInterval = 86_400
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    activityOverview
                    syncHealthCard
                    devicesCard
                    recentEventsCard
                }
                .padding(20)
            }
            .background(DS.ColorToken.background)
            .navigationTitle(AppLocalization.localized("dashboard.activity.title", value: "Salon Activity"))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await runCheck() }
                    } label: {
                        Label(
                            isChecking
                                ? AppLocalization.localized("dashboard.activity.checking", value: "Checking")
                                : AppLocalization.localized("dashboard.activity.check_now", value: "Check Now"),
                            systemImage: isChecking ? "hourglass" : "arrow.clockwise.icloud"
                        )
                    }
                    .disabled(isChecking)
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.localized("common.close", value: "Close")) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
        .frame(minWidth: 600, idealWidth: 720, maxWidth: 820, minHeight: 540, idealHeight: 680, maxHeight: 820)
        .task {
            await refreshActivityContext()
        }
    }

    private var activityOverview: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
            ActivityMetricCard(
                title: AppLocalization.localized("dashboard.activity.icloud", value: "iCloud"),
                value: syncStateTitle,
                detail: monitor.networkState.displayLabel,
                systemImage: monitor.statusIconName,
                tint: syncTint
            )

            ActivityMetricCard(
                title: AppLocalization.localized("dashboard.activity.pending", value: "Pending"),
                value: "\(max(monitor.pendingLocalChangeCount, monitor.offlineBufferedMutationCount))",
                detail: monitor.pendingChangesSummary
                    ?? AppLocalization.localized("dashboard.activity.pending_clear", value: "No waiting changes"),
                systemImage: "tray.and.arrow.up.fill",
                tint: monitor.pendingChangesSummary == nil ? DS.ColorToken.success : DS.ColorToken.warning
            )

            ActivityMetricCard(
                title: AppLocalization.localized("dashboard.activity.devices", value: "Devices"),
                value: "\(visibleDevices.count)",
                detail: devicesOverview,
                systemImage: "ipad.and.iphone",
                tint: DS.ColorToken.info
            )
        }
    }

    private var syncHealthCard: some View {
        ActivityCard(accent: syncTint) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: monitor.statusIconName)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(syncTint)
                    .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(monitor.healthHeadline)
                            .font(.headline)
                        Spacer(minLength: 12)
                        ActivityPill(title: syncStateTitle, tint: syncTint)
                    }

                    Text(monitor.healthDetail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !monitor.healthIssues.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(monitor.healthIssues.prefix(3)) { issue in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: issueIcon(for: issue))
                                        .foregroundStyle(issueTint(for: issue))
                                        .frame(width: 18)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(issue.title)
                                            .font(.caption.weight(.semibold))
                                        Text(issue.detail)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            }
        }
    }

    private var devicesCard: some View {
        ActivityCard(accent: DS.ColorToken.info) {
            ActivityCardHeader(
                title: AppLocalization.localized("dashboard.activity.devices_title", value: "Synced Devices"),
                detail: devicesOverview,
                systemImage: "antenna.radiowaves.left.and.right"
            )

            if visibleDevices.isEmpty {
                ActivityEmptyState(
                    title: AppLocalization.localized("dashboard.activity.no_devices", value: "No synced devices yet"),
                    detail: AppLocalization.localized(
                        "dashboard.activity.no_devices_detail",
                        value: "The current device appears here after iCloud finishes its first heartbeat."
                    ),
                    systemImage: "icloud.slash"
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(visibleDevices.prefix(4)) { device in
                        ActivityDeviceRow(
                            name: displayName(for: device),
                            detail: deviceSubtitle(for: device),
                            status: deviceStatusTitle(for: device),
                            statusTint: statusTint(for: device),
                            lastSeen: relativeText(for: device.lastSyncAt),
                            isCurrent: device.deviceID == DeviceIdentity.currentID
                        )

                        if device.deviceID != visibleDevices.prefix(4).last?.deviceID {
                            Divider().padding(.leading, 38)
                        }
                    }
                }
            }

            if !activePresenceRecords.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text(AppLocalization.localized("dashboard.activity.live_presence", value: "Live Presence"))
                        .font(.subheadline.weight(.semibold))
                    ForEach(activePresenceRecords.prefix(3)) { record in
                        Label(presenceSummary(for: record), systemImage: "eye.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var recentEventsCard: some View {
        ActivityCard(accent: DS.ColorToken.primary) {
            ActivityCardHeader(
                title: AppLocalization.localized("dashboard.activity.section", value: "Recent Activity"),
                detail: recentEventsSummary,
                systemImage: "clock.arrow.2.circlepath"
            )

            if monitor.syncEvents.isEmpty {
                ActivityEmptyState(
                    title: AppLocalization.localized("dashboard.activity.empty_title", value: "No recent activity"),
                    detail: AppLocalization.localized("dashboard.activity.empty_detail", value: "Worker actions and sync events will appear here."),
                    systemImage: "checkmark.circle"
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(monitor.syncEvents.prefix(12)) { event in
                        ActivityRow(event: event, devices: devices)

                        if event.id != monitor.syncEvents.prefix(12).last?.id {
                            Divider().padding(.leading, 48)
                        }
                    }
                }
            }
        }
    }

    private var visibleDevices: [DeviceMetadata] {
        var seen = Set<UUID>()
        return devices
            .sorted { $0.lastSyncAt > $1.lastSyncAt }
            .filter { device in
                guard !seen.contains(device.deviceID) else { return false }
                seen.insert(device.deviceID)
                return true
            }
    }

    private var activePresenceRecords: [PresenceRecord] {
        let cutoff = Date().addingTimeInterval(-freshnessWindow)
        var seen = Set<UUID>()
        return presenceRecords
            .filter { $0.updatedAt >= cutoff }
            .sorted { $0.updatedAt > $1.updatedAt }
            .filter { record in
                guard !seen.contains(record.deviceID) else { return false }
                seen.insert(record.deviceID)
                return true
            }
    }

    private var syncStateTitle: String {
        switch monitor.syncState {
        case .idle:
            return monitor.pendingChangesSummary == nil
                ? AppLocalization.localized("dashboard.activity.synced", value: "Ready")
                : AppLocalization.localized("dashboard.activity.waiting", value: "Waiting")
        case .syncing:
            return AppLocalization.localized("dashboard.activity.syncing", value: "Syncing")
        case .error:
            return AppLocalization.localized("dashboard.activity.needs_attention", value: "Needs Attention")
        }
    }

    private var syncTint: Color {
        switch monitor.statusTint {
        case .success: return DS.ColorToken.success
        case .neutral: return DS.ColorToken.info
        case .warning: return DS.ColorToken.warning
        case .danger: return DS.ColorToken.danger
        }
    }

    private var devicesOverview: String {
        guard !visibleDevices.isEmpty else {
            return AppLocalization.localized("dashboard.activity.devices_waiting", value: "Waiting for first heartbeat")
        }

        let online = visibleDevices.filter { freshness(for: $0.lastSyncAt) == .online }.count
        let active = activePresenceRecords.count
        return String.localizedStringWithFormat(
            AppLocalization.localized(
                "dashboard.activity.devices_summary_fmt",
                value: "%d online, %d active now"
            ),
            online,
            active
        )
    }

    private var recentEventsSummary: String {
        guard let first = monitor.syncEvents.first else {
            return AppLocalization.localized("dashboard.activity.events_waiting", value: "Nothing logged yet")
        }

        return String(
            format: AppLocalization.localized("dashboard.activity.last_event_fmt", value: "Latest %@"),
            relativeText(for: first.startedAt)
        )
    }

    @MainActor
    private func refreshActivityContext() async {
        await monitor.refreshAccountStatus()
        monitor.updateDeviceMetadata()
        monitor.cleanupStalePresence()
    }

    @MainActor
    private func runCheck() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        await monitor.refreshAccountStatus()
        if monitor.canForceSync {
            await monitor.forceSync()
        }
        monitor.updateDeviceMetadata()
        monitor.cleanupStalePresence()
    }

    private func displayName(for device: DeviceMetadata) -> String {
        let trimmed = device.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty
            ? AppLocalization.localized("common.unknown_device", value: "Unknown Device")
            : trimmed
    }

    private func deviceSubtitle(for device: DeviceMetadata) -> String {
        let model = device.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let os = device.osVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayModel = model.isEmpty ? AppLocalization.localized("settings.devices.model_unknown", value: "Unknown Model") : model
        let displayOS = os.isEmpty ? AppLocalization.localized("settings.devices.os_unknown", value: "Unknown OS") : os
        return "\(displayModel) - \(displayOS)"
    }

    private func deviceStatusTitle(for device: DeviceMetadata) -> String {
        switch freshness(for: device.lastSyncAt) {
        case .online: return AppLocalization.localized("settings.devices.online", value: "Online")
        case .recent: return AppLocalization.localized("settings.devices.recently_seen", value: "Recently Seen")
        case .stale: return AppLocalization.localized("settings.devices.needs_check", value: "Needs Check")
        }
    }

    private func statusTint(for device: DeviceMetadata) -> Color {
        switch freshness(for: device.lastSyncAt) {
        case .online: return DS.ColorToken.success
        case .recent: return DS.ColorToken.info
        case .stale: return DS.ColorToken.warning
        }
    }

    private func freshness(for date: Date) -> ActivityDeviceFreshness {
        let age = Date().timeIntervalSince(date)
        if age < freshnessWindow { return .online }
        if age < recentWindow { return .recent }
        return .stale
    }

    private func presenceSummary(for record: PresenceRecord) -> String {
        let deviceName = record.deviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? AppLocalization.localized("common.unknown_device", value: "Unknown Device")
            : record.deviceName
        let recordType = record.recordType?.trimmingCharacters(in: .whitespacesAndNewlines)
        let viewing = recordType?.isEmpty == false
            ? String(format: AppLocalization.localized("dashboard.activity.viewing_fmt", value: "viewing %@"), recordType!.capitalized)
            : AppLocalization.localized("dashboard.activity.active_now", value: "active now")
        return "\(deviceName) \(viewing) - \(relativeText(for: record.updatedAt))"
    }

    private func issueIcon(for issue: CloudKitMonitor.SyncHealthIssue) -> String {
        switch issue.severity {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .danger: return "xmark.octagon.fill"
        }
    }

    private func issueTint(for issue: CloudKitMonitor.SyncHealthIssue) -> Color {
        switch issue.severity {
        case .info: return DS.ColorToken.info
        case .warning: return DS.ColorToken.warning
        case .danger: return DS.ColorToken.danger
        }
    }

    private func relativeText(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
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

private enum ActivityDeviceFreshness {
    case online
    case recent
    case stale
}

private struct ActivityCard<Content: View>: View {
    let accent: Color
    let content: Content

    init(accent: Color, @ViewBuilder content: () -> Content) {
        self.accent = accent
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(accent)
                .frame(width: 4)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

private struct ActivityCardHeader: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(DS.ColorToken.primary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ActivityMetricCard: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: systemImage)
                    .font(.headline)
                    .foregroundStyle(tint)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tint.opacity(0.20), lineWidth: 1)
        }
    }
}

private struct ActivityDeviceRow: View {
    let name: String
    let detail: String
    let status: String
    let statusTint: Color
    let lastSeen: String
    let isCurrent: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isCurrent ? "desktopcomputer.and.macbook" : "ipad.and.iphone")
                .foregroundStyle(statusTint)
                .frame(width: 26)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(name)
                        .font(.subheadline.weight(.semibold))
                    if isCurrent {
                        ActivityPill(
                            title: AppLocalization.localized("settings.devices.this_device", value: "This Device"),
                            tint: DS.ColorToken.info
                        )
                    }
                    Spacer(minLength: 8)
                    Text(lastSeen)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ActivityPill(title: status, tint: statusTint)
            }
        }
        .padding(.vertical, 10)
    }
}

private struct ActivityPill: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

private struct ActivityEmptyState: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }
}
