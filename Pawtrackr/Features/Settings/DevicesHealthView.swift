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

    private let freshnessWindow: TimeInterval = 600

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
                    }
                }

                Button {
                    Task {
                        await refreshDeviceStatus()
                    }
                } label: {
                    Label(devicesLocalized("settings.devices.refresh", value: "Refresh Device Status"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }

            DevicesCard {
                SectionHeader(
                    title: devicesLocalized("settings.devices.connected_devices", value: "Synced Devices"),
                    systemImage: "ipad.and.iphone"
                )

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
                                status: deviceStatusTitle(for: device),
                                statusTint: statusTint(for: device),
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
                    title: devicesLocalized("settings.devices.live_presence", value: "Live Presence"),
                    systemImage: "person.crop.circle.badge.checkmark"
                )

                if activePresenceRecords.isEmpty {
                    DevicesEmptyState(
                        title: devicesLocalized("settings.devices.no_active_presence", value: "No active record viewers"),
                        detail: devicesLocalized(
                            "settings.devices.no_active_presence_detail",
                            value: "When another synced device opens a client or pet record, its activity appears here for quick coordination."
                        ),
                        systemImage: "eye.slash"
                    )
                } else {
                    VStack(spacing: 0) {
                        ForEach(activePresenceRecords) { record in
                            PresenceRow(
                                deviceName: presenceName(for: record),
                                detail: presenceDetail(for: record),
                                updatedText: relativeText(for: record.updatedAt)
                            )

                            if record.deviceID != activePresenceRecords.last?.deviceID {
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

    private var currentStatusTitle: String {
        guard let currentDevice else {
            return monitor.accountState.isAvailable
                ? devicesLocalized("settings.devices.recent", value: "Ready")
                : monitor.accountState.displayLabel
        }

        return deviceStatusTitle(for: currentDevice)
    }

    private var currentStatusTint: Color {
        guard let currentDevice else {
            return monitor.accountState.isAvailable ? .blue : .orange
        }

        return statusTint(for: currentDevice)
    }

    private var currentStatusIcon: String {
        guard let currentDevice else {
            return monitor.accountState.isAvailable ? "wave.3.right.circle.fill" : "exclamationmark.triangle.fill"
        }

        return isFresh(currentDevice.lastSyncAt) ? "checkmark.circle.fill" : "clock.badge.exclamationmark.fill"
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

    private func deviceSubtitle(for device: DeviceMetadata) -> String {
        let model = device.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let os = device.osVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayModel = model.isEmpty ? devicesLocalized("settings.devices.model_unknown", value: "Unknown Model") : model
        let displayOS = os.isEmpty ? devicesLocalized("settings.devices.os_unknown", value: "Unknown OS") : os
        return "\(displayModel) - \(displayOS)"
    }

    private func deviceStatusTitle(for device: DeviceMetadata) -> String {
        isFresh(device.lastSyncAt)
            ? devicesLocalized("settings.devices.online", value: "Online")
            : devicesLocalized("settings.devices.offline", value: "Offline")
    }

    private func statusTint(for device: DeviceMetadata) -> Color {
        isFresh(device.lastSyncAt) ? .green : .orange
    }

    private func isFresh(_ date: Date) -> Bool {
        Date().timeIntervalSince(date) < freshnessWindow
    }

    private func presenceDetail(for record: PresenceRecord) -> String {
        guard let recordType = record.recordType,
              !recordType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return devicesLocalized("settings.devices.not_viewing", value: "Not viewing a record")
        }

        return devicesLocalizedFormat("settings.devices.viewing_fmt", value: "Viewing %@", recordType.capitalized)
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
    let lastSeen: String
    let isCurrentDevice: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(statusTint)
                .frame(width: 10, height: 10)
                .padding(.top, 7)

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
