//
//  DeviceMetadata.swift
//  Pawtrackr
//
//  Tracks device-specific info synced across the iCloud account.
//  Allows owners to see which devices (Reception iPad, Groomer iPhone) are active.
//

import Foundation
import SwiftData

@Model
final class DeviceMetadata {
    // Non-optional properties have defaults — required by CloudKit-backed
    // SwiftData. Uniqueness is NOT enforced across CloudKit replicas, so the
    // upsert path in CloudKitMonitor dedupes by deviceID instead.

    /// Matches DeviceIdentity.currentID
    var deviceID: UUID = UUID()

    /// User-defined name (e.g. "Reception iPad")
    var name: String = ""

    /// Auto-detected model name
    var model: String = ""

    /// OS version
    var osVersion: String = ""

    /// Last time this specific device pushed an update to iCloud
    var lastSyncAt: Date = Date()

    init(deviceID: UUID, name: String, model: String, osVersion: String) {
        self.deviceID = deviceID
        self.name = name
        self.model = model
        self.osVersion = osVersion
        self.lastSyncAt = .now
    }
}
