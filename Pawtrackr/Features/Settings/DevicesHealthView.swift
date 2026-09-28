import Foundation
import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
#endif

private func devicesLocalized(_ key: String, value: String) -> String {
    NSLocalizedString(key, value: value, comment: "")
}

private func devicesLocalizedFormat(_ key: String, value: String, _ arguments: CVarArg...) -> String {
    String(format: devicesLocalized(key, value: value), locale: .current, arguments: arguments)
}

struct DevicesHealthView: View {
    @Query(sort: \DeviceMetadata.lastSyncAt, order: .reverse) private var devices: [DeviceMetadata]
    @Query(sort: \PresenceRecord.updatedAt, order: .reverse) private var presenceRecords: [PresenceRecord]
    @State private var monitor = CloudKitMonitor.shared
    @State private var isRefreshing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DevicesCard {
                SectionHeader(
                    title: devicesLocalized("settings.devices.current_device", value: "Current Device"),
                    systemImage: "iphone.gen3"
                )

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: currentStatusIcon)
                        .font(.title2)
                        .foregroundStyle(currentStatusTint)
                        .frame(width: 34, height: 34)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(currentDeviceName)
                                .font(.headline)
                            StatusPill(title: currentStatusTitle, tint: currentStatusTint)
                        }

                        Text(currentDeviceSubtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        InfoLine(
                            title: devicesLocalized("settings.devices.device_id", value: "Device ID"),
                            value: shortID(DeviceIdentity.currentID)
                        )
                        InfoLine(
                            title: devicesLocalized("settings.devices.last_heartbeat", value: "Last Heartbeat"),
                            value: currentHeartbeatText
                        )
                        InfoLine(
                            title: devicesLocalized("settings.devices.icloud", value: "iCloud"),
                            value: monitor.accountState.displayLabel
                        )
                        InfoLine(
                            title: devicesLocalized("settings.devices.network", value: "Network"),
                            value: monitor.networkState.displayLabel
                        )
                    }
                }

                Button {
                    Task {
                        await runDeviceRefresh()
                    }
                } label: {
                    Label(deviceRefreshTitle, systemImage: isRefreshing ? "hourglass" : "arrow.clockwise.icloud")
                }
                .buttonStyle(.bordered)
                .disabled(isRefreshing)
            }

            DevicesCard {
                SectionHeader(
                    title: devicesLocalized("settings.devices.connected_devices", value: "Synced Devices"),
                    systemImage: "ipad.and.iphone"
                )
                Text(devicesSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if visibleDevices.isEmpty {
                    DevicesEmptyState(
                        title: devicesLocalized("settings.devices.no_synced_devices", value: "No synced devices yet"),
                        detail: devicesLocalized(
                            "settings.devices.no_synced_devices_detail",
                            value: "Pawtrackr will list signed-in iPhones, iPads, and Macs here after iCloud finishes its first device heartbeat."
                        ),
                        systemImage: "icloud.slash"
                    )
                } else {
                    VStack(spacing: 0) {
                        ForEach(visibleDevices) { device in
                            SyncedDeviceRow(
                                name: displayName(for: device),
                                subtitle: deviceSubtitle(for: device),
                                status: rowStatusTitle(for: device),
                                statusTint: rowStatusTint(for: device),
                                statusIcon: rowStatusIcon(for: device),
                                lastSeen: relativeText(for: device.lastSyncAt),
                                isCurrentDevice: device.deviceID == DeviceIdentity.currentID
                            )

                            if device.deviceID != visibleDevices.last?.deviceID {
                                Divider()
                                    .padding(.leading, 42)
                            }
                        }
                    }
                }
            }

            DevicesCard {
                SectionHeader(
                    title: devicesLocalized("settings.devices.recently_open_title", value: "Recently Open Elsewhere"),
                    systemImage: "person.crop.circle"
                )

                if recentlyOpenElsewhere.isEmpty {
                    DevicesEmptyState(
                        title: devicesLocalized("settings.devices.no_recent_presence", value: "Nothing open elsewhere recently"),
                        detail: devicesLocalized(
                            "settings.devices.no_recent_presence_detail",
                            value: "When another device opens a client or pet, it shows here once iCloud delivers that update."
                        ),
                        systemImage: "eye.slash"
                    )
                } else {
                    VStack(spacing: 0) {
                        ForEach(recentlyOpenElsewhere) { record in
                            PresenceRow(
                                deviceName: presenceName(for: record),
                                detail: DeviceActivityPolicy.presenceSummary(
                                    deviceName: record.deviceName,
                                    recordType: record.recordType
                                ),
                                updatedText: relativeText(for: record.updatedAt)
                            )

                            if record.deviceID != recentlyOpenElsewhere.last?.deviceID {
                                Divider()
                                    .padding(.leading, 42)
                            }
                        }
                    }
                }
            }
        }
        .task {
            await refreshDeviceStatus()
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

    private var recentlyOpenElsewhere: [PresenceRecord] {
        DeviceActivityPolicy.recentlyOpenElsewhere(
            presenceRecords,
            currentDeviceID: DeviceIdentity.currentID,
            now: Date()
        )
    }

    private var devicesSummary: String {
        guard !visibleDevices.isEmpty else {
            return devicesLocalized(
                "settings.devices.summary.empty",
                value: "Device heartbeats will appear after iCloud finishes syncing."
            )
        }

        return devicesLocalizedFormat(
            "settings.devices.summary_recent_fmt",
            value: "%1$d device(s), %2$d other(s) seen recently",
            visibleDevices.count,
            otherDevicesSeenRecently
        )
    }

    /// This device's own heartbeat is written locally, so only other
    /// devices count.
    private var otherDevicesSeenRecently: Int {
        visibleDevices.filter {
            $0.deviceID != DeviceIdentity.currentID && heartbeatAge(for: $0) == .recent
        }.count
    }

    private var currentDevice: DeviceMetadata? {
        visibleDevices.first { $0.deviceID == DeviceIdentity.currentID }
    }

    private var currentDeviceName: String {
        if let currentDevice {
            return displayName(for: currentDevice, fallback: DeviceIdentity.currentName)
        }

        if let storedName = UserDefaults.standard.string(forKey: AppSettingsKeys.deviceName),
           !storedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return storedName
        }

        return DeviceIdentity.currentName
    }

    private var currentDeviceSubtitle: String {
        if let currentDevice {
            return deviceSubtitle(for: currentDevice)
        }

        return "\(fallbackDeviceModel) - \(fallbackOSVersion)"
    }

    private var currentHeartbeatText: String {
        guard let currentDevice else {
            return devicesLocalized("settings.devices.waiting_heartbeat", value: "Waiting for first heartbeat")
        }

        return currentDevice.lastSyncAt.formatted(date: .abbreviated, time: .shortened)
    }

    /// This device's status is its backup status. Its heartbeat is written
    /// locally before anything uploads, so it can't vouch for iCloud.
    private var currentStatusTitle: String {
        monitor.statusLabel.title
    }

    private var currentStatusTint: Color {
        switch monitor.statusTint {
        case .success: return .green
        case .neutral: return .blue
        case .warning: return .orange
        case .danger: return .red
        }
    }

    private var currentStatusIcon: String {
        monitor.statusIconName
    }

    private var deviceRefreshTitle: String {
        isRefreshing
            ? devicesLocalized("settings.devices.refreshing", value: "Checking iCloud and devices...")
            : devicesLocalized("settings.devices.refresh", value: "Check iCloud & Devices")
    }

    private var fallbackDeviceModel: String {
        #if os(iOS)
        UIDevice.current.model
        #elseif os(macOS)
        "Mac"
        #else
        devicesLocalized("settings.devices.model_unknown", value: "Unknown Model")
        #endif
    }

    private var fallbackOSVersion: String {
        #if os(iOS)
        "iOS \(UIDevice.current.systemVersion)"
        #elseif os(macOS)
        "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
        #else
        devicesLocalized("settings.devices.os_unknown", value: "Unknown OS")
        #endif
    }

    @MainActor
    private func refreshDeviceStatus() async {
        await monitor.refreshAccountStatus()
        monitor.updateDeviceMetadata()
        monitor.cleanupStalePresence()
    }

    @MainActor
    private func runDeviceRefresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        await monitor.refreshAccountStatus()
        if monitor.canForceSync {
            await monitor.forceSync()
        }
        monitor.updateDeviceMetadata()
        monitor.cleanupStalePresence()
    }

    private func displayName(for device: DeviceMetadata, fallback: String? = nil) -> String {
        let trimmed = device.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return fallback ?? devicesLocalized("settings.devices.unnamed_device", value: "Unnamed Device")
    }

    private func presenceName(for record: PresenceRecord) -> String {
        let trimmed = record.deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty
            ? devicesLocalized("settings.devices.unnamed_device", value: "Unnamed Device")
            : trimmed
    }

    private func heartbeatAge(for device: DeviceMetadata) -> DeviceActivityPolicy.HeartbeatAge {
        DeviceActivityPolicy.HeartbeatAge(lastSeen: device.lastSyncAt, now: Date())
    }

    private func deviceSubtitle(for device: DeviceMetadata) -> String {
        let model = device.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let os = device.osVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayModel = model.isEmpty ? devicesLocalized("settings.devices.model_unknown", value: "Unknown Model") : model
        let displayOS = os.isEmpty ? devicesLocalized("settings.devices.os_unknown", value: "Unknown OS") : os
        return "\(displayModel) - \(displayOS)"
    }

    private func rowStatusTitle(for device: DeviceMetadata) -> String {
        device.deviceID == DeviceIdentity.currentID ? currentStatusTitle : heartbeatAge(for: device).title
    }

    /// Other devices are never green: a heartbeat is not a backup.
    private func rowStatusTint(for device: DeviceMetadata) -> Color {
        guard device.deviceID != DeviceIdentity.currentID else { return currentStatusTint }
        switch heartbeatAge(for: device) {
        case .recent, .lastDay: return .blue
        case .stale: return .orange
        }
    }

    private func rowStatusIcon(for device: DeviceMetadata) -> String {
        guard device.deviceID != DeviceIdentity.currentID else { return currentStatusIcon }
        switch heartbeatAge(for: device) {
        case .recent, .lastDay: return "clock"
        case .stale: return "exclamationmark.triangle.fill"
        }
    }

    private func relativeText(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func shortID(_ id: UUID) -> String {
        String(id.uuidString.prefix(8))
    }
}

private struct DevicesCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

private struct SectionHeader: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
    }
}

private struct StatusPill: View {
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

private struct InfoLine: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.medium)
        }
        .font(.caption)
    }
}

private struct SyncedDeviceRow: View {
    let name: String
    let subtitle: String
    let status: String
    let statusTint: Color
    let statusIcon: String
    let lastSeen: String
    let isCurrentDevice: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: statusIcon)
                .foregroundStyle(statusTint)
                .frame(width: 22)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(name)
                        .font(.subheadline.weight(.semibold))
                    if isCurrentDevice {
                        StatusPill(
                            title: devicesLocalized("settings.devices.this_device", value: "This Device"),
                            tint: .blue
                        )
                    }
                    Spacer(minLength: 8)
                    Text(lastSeen)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(status)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(statusTint)
            }
        }
        .padding(.vertical, 10)
    }
}

private struct PresenceRow: View {
    let deviceName: String
    let detail: String
    let updatedText: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "eye.fill")
                .foregroundStyle(.blue)
                .frame(width: 18)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(deviceName)
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 8)
                    Text(updatedText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 10)
    }
}

private struct DevicesEmptyState: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }
}
