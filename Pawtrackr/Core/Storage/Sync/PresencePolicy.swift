//
//  PresencePolicy.swift
//  Pawtrackr
//
//  When this device writes its PresenceRecord ("this client is open here"),
//  and when another device's record earns the "Recently open on <device>"
//  chip in Client and Pet details.
//
//  Every assignment to a mirrored row uploads it to iCloud and imports it on
//  every other device, so the writer compares before assigning and only
//  moves updatedAt when a field changed or a heartbeat is due. Another
//  device's record arrives only when CloudKit imports it, sometimes minutes
//  late, so the chip says "recently", never "now" or "live".
//

import Foundation
import SwiftData

enum PresencePolicy {
    /// How often an open Client or Pet details screen re-stamps its record.
    static let heartbeatInterval: TimeInterval = 2 * 60
    /// A heartbeat is written once the stamp is at least this old: a little
    /// under the interval, so a loop that wakes on time never skips a beat.
    static let heartbeatDueAge: TimeInterval = 90
    /// Another device's record shows the chip while it's this fresh.
    static let chipFreshness: TimeInterval = 5 * 60
    /// How often an open details screen re-reads presence for the chip.
    static let chipRefreshInterval: TimeInterval = 30

    enum Decision: Equatable, Sendable {
        /// Nothing changed and no heartbeat is due: write nothing.
        case skip
        case insert
        case update
    }

    /// What this device's record should do, given what's stored now.
    static func decision(
        existingDeviceName: String?,
        existingViewingRecordID: UUID?,
        existingRecordType: String?,
        existingUpdatedAt: Date?,
        hasExisting: Bool,
        deviceName: String,
        viewingRecordID: UUID?,
        recordType: String?,
        now: Date
    ) -> Decision {
        guard hasExisting else {
            // Nothing to clear, and a record that says "nothing open" is
            // only noise for the other devices.
            return viewingRecordID == nil ? .skip : .insert
        }
        let fieldsChanged = existingDeviceName != deviceName
            || existingViewingRecordID != viewingRecordID
            || existingRecordType != recordType
        if fieldsChanged { return .update }
        guard viewingRecordID != nil, let existingUpdatedAt else { return .skip }
        return now.timeIntervalSince(existingUpdatedAt) >= heartbeatDueAge ? .update : .skip
    }

    /// Writes this device's presence into `context` when the decision says
    /// so, and saves. Returns true when something was saved.
    @discardableResult
    static func apply(
        in context: ModelContext,
        deviceID: UUID,
        deviceName: String,
        viewingRecordID: UUID?,
        recordType: String?,
        now: Date
    ) throws -> Bool {
        var descriptor = FetchDescriptor<PresenceRecord>(
            predicate: #Predicate<PresenceRecord> { $0.deviceID == deviceID },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        let existing = try context.fetch(descriptor).first

        switch decision(
            existingDeviceName: existing?.deviceName,
            existingViewingRecordID: existing?.viewingRecordID,
            existingRecordType: existing?.recordType,
            existingUpdatedAt: existing?.updatedAt,
            hasExisting: existing != nil,
            deviceName: deviceName,
            viewingRecordID: viewingRecordID,
            recordType: recordType,
            now: now
        ) {
        case .skip:
            return false
        case .insert:
            let record = PresenceRecord(deviceID: deviceID, deviceName: deviceName)
            record.viewingRecordID = viewingRecordID
            record.recordType = recordType
            record.updatedAt = now
            context.insert(record)
        case .update:
            guard let existing else { return false }
            if existing.deviceName != deviceName { existing.deviceName = deviceName }
            if existing.viewingRecordID != viewingRecordID { existing.viewingRecordID = viewingRecordID }
            if existing.recordType != recordType { existing.recordType = recordType }
            existing.updatedAt = now
        }

        guard context.hasChanges else { return false }
        try context.save()
        return true
    }

    /// The newest record from another device that has `recordID` open and
    /// was stamped within `chipFreshness`, or nil. A stamp slightly in the
    /// future (another device's clock running ahead) still counts.
    static func recentlyOpenElsewhere(
        _ records: [PresenceRecord],
        recordID: UUID,
        currentDeviceID: UUID,
        now: Date
    ) -> PresenceRecord? {
        records
            .filter { record in
                record.viewingRecordID == recordID
                    && record.deviceID != currentDeviceID
                    && now.timeIntervalSince(record.updatedAt) <= chipFreshness
            }
            .max { $0.updatedAt < $1.updatedAt }
    }

    /// "Recently open on Front Desk iPad".
    static func chipTitle(deviceName: String) -> String {
        let trimmed = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "Unknown Device" else {
            return AppLocalization.localized("presence.recently_open_unnamed", value: "Recently open on another device")
        }
        return String(
            format: AppLocalization.localized("presence.recently_open_fmt", value: "Recently open on %@"),
            trimmed
        )
    }
}
