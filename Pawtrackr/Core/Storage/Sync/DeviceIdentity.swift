//
//  DeviceIdentity.swift
//  Pawtrackr
//
//  Stable per-install identifier used for conflict diagnostics.
//

import Foundation
#if os(iOS)
import UIKit
#endif

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

    static var currentName: String {
#if os(macOS)
        Host.current().localizedName ?? "Unknown Device"
#else
        UIDevice.current.name
#endif
    }
}
