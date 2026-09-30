//
//  PresenceRecord.swift
//  Pawtrackr
//
//  Legacy metadata retained for compatibility with existing stores.
//  The local app does not publish or read device presence.
//

import Foundation
import SwiftData

@Model
final class PresenceRecord {

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
