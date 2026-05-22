//
//  DeviceIdentity.swift
//  Pawtrackr
//
//  Stable per-install identifier used for conflict diagnostics.
//

import Foundation

enum DeviceIdentity {
    private static let defaultsKey = "PawtrackrDeviceIdentityUUID"

    static var currentID: UUID {
        if let raw = UserDefaults.standard.string(forKey: defaultsKey),
           let uuid = UUID(uuidString: raw) {
            return uuid
        }

        let uuid = UUID()
        UserDefaults.standard.set(uuid.uuidString, forKey: defaultsKey)
        return uuid
    }
}
