//
//  DeviceActivityPolicy.swift
//  Pawtrackr
//
//  Wording for other devices' heartbeats and presence. Both reach this
//  device only when CloudKit imports them, sometimes minutes late, so a
//  fresh record means "recently", never "live", "online" or "active now".
//  This device's own row speaks for its backup status instead
//  (BackupStatusLabel): its heartbeat is written locally, before anything
//  has uploaded.
//

import Foundation

enum DeviceActivityPolicy {
    /// A heartbeat or presence record newer than this counts as recent.
    static let recentWindow: TimeInterval = 10 * 60
    /// Older than this, the device hasn't been seen for over a day.
    static let dayWindow: TimeInterval = 24 * 60 * 60

    enum HeartbeatAge: Equatable, Sendable {
        case recent
        case lastDay
        case stale

        init(lastSeen: Date, now: Date) {
            // A clock a little ahead on the other device still reads as recent.
            let age = now.timeIntervalSince(lastSeen)
            if age < DeviceActivityPolicy.recentWindow {
                self = .recent
            } else if age < DeviceActivityPolicy.dayWindow {
                self = .lastDay
            } else {
                self = .stale
            }
        }

        var title: String {
            switch self {
            case .recent:
                return AppLocalization.localized("settings.devices.seen_recently", value: "Seen recently")
            case .lastDay:
                return AppLocalization.localized("settings.devices.seen_last_day", value: "Seen in the last day")
            case .stale:
                return AppLocalization.localized("settings.devices.not_seen_day", value: "Not seen for over a day")
            }
        }
    }

    /// Other devices' presence records updated within the recent window,
    /// newest first, one per device. This device's own record is left out:
    /// it only says what this screen already knows.
    static func recentlyOpenElsewhere(
        _ records: [PresenceRecord],
        currentDeviceID: UUID,
        now: Date
    ) -> [PresenceRecord] {
        let cutoff = now.addingTimeInterval(-recentWindow)
        var seen = Set<UUID>()
        return records
            .filter { $0.deviceID != currentDeviceID && $0.updatedAt >= cutoff }
            .sorted { $0.updatedAt > $1.updatedAt }
            .filter { seen.insert($0.deviceID).inserted }
    }

    /// "Front Desk iPad had a client open". The record type is stored as a
    /// raw English word ("client", "pet"), so it's mapped to a translated
    /// phrase rather than shown as is.
    static func presenceSummary(deviceName: String, recordType: String?) -> String {
        let trimmedName = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmedName.isEmpty
            ? AppLocalization.localized("settings.devices.unnamed_device", value: "Unnamed Device")
            : trimmedName
        let format: String
        switch recordType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "client":
            format = AppLocalization.localized("settings.devices.presence_client_fmt", value: "%@ had a client open")
        case "pet":
            format = AppLocalization.localized("settings.devices.presence_pet_fmt", value: "%@ had a pet open")
        default:
            format = AppLocalization.localized("settings.devices.presence_app_fmt", value: "%@ had Pawtrackr open")
        }
        return String(format: format, name)
    }
}
