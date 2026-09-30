//
//  DeviceMetadata.swift
//  Pawtrackr
//
//  Legacy metadata retained so existing stores remain compatible.
//

import Foundation
import SwiftData

@Model
final class DeviceMetadata {

    /// Matches DeviceIdentity.currentID
    var deviceID: UUID = UUID()

    /// User-defined name (e.g. "Reception iPad")
    var name: String = ""

    /// Auto-detected model name
    var model: String = ""

    /// OS version
    var osVersion: String = ""
    var lastSyncAt: Date = Date()

    init(deviceID: UUID, name: String, model: String, osVersion: String) {
        self.deviceID = deviceID
        self.name = name
        self.model = model
        self.osVersion = osVersion
        self.lastSyncAt = .now
    }
}
