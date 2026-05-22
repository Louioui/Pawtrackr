//
//  PresenceRecord.swift
//  Pawtrackr
//
//  Tracks which device is viewing which record in real-time.
//

import Foundation
import SwiftData

@Model
final class PresenceRecord {
    // Non-optional properties have defaults — required by CloudKit-backed
    // SwiftData. Uniqueness is NOT enforced across CloudKit replicas, so the
    // upsert path in CloudKitMonitor dedupes by deviceID instead.

    /// Matches DeviceIdentity.currentID
    var deviceID: UUID = UUID()

    /// The name of the device viewing the record
    var deviceName: String = ""

    /// The UUID of the Client or Pet being viewed
    var viewingRecordID: UUID?

    /// The type of record (e.g. "client", "pet")
    var recordType: String?

    /// When this presence was last heartbeated
    var updatedAt: Date = Date()

    init(deviceID: UUID, deviceName: String) {
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.updatedAt = .now
    }
}
