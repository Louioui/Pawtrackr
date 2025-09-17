
import SwiftUI
import Combine

final class AppSettings: ObservableObject {
    @Published var isBiometricLockEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isBiometricLockEnabled, forKey: "isBiometricLockEnabled")
        }
    }

    // 4-digit App PIN (default 1994)
    @Published var appPIN: String {
        didSet { UserDefaults.standard.set(appPIN, forKey: "appPIN") }
    }

    // Last time the PIN was changed (for UI display)
    @Published var lastPINChangeDate: Date? {
        didSet { if let d = lastPINChangeDate { UserDefaults.standard.set(d, forKey: "lastPINChangeDate") } }
    }

    // Auto-lock behaviors
    @Published var autoLockOnBackground: Bool {
        didSet { UserDefaults.standard.set(autoLockOnBackground, forKey: "autoLockOnBackground") }
    }
    @Published var autoLockAfterInactivity: Bool {
        didSet { UserDefaults.standard.set(autoLockAfterInactivity, forKey: "autoLockAfterInactivity") }
    }
    // Fixed idle threshold (minutes) for now; can make user-configurable later
    let idleLockMinutes: Int = 5

    private let biometricKey = "isBiometricLockEnabled"

    init() {
        // Read initial value from UserDefaults, default to true
        self.isBiometricLockEnabled = UserDefaults.standard.object(forKey: biometricKey) as? Bool ?? true
        // Register default value if not already set
        UserDefaults.standard.register(defaults: [biometricKey: true])

        self.appPIN = (UserDefaults.standard.string(forKey: "appPIN") ?? "1994")
        self.lastPINChangeDate = UserDefaults.standard.object(forKey: "lastPINChangeDate") as? Date
        self.autoLockOnBackground = UserDefaults.standard.object(forKey: "autoLockOnBackground") as? Bool ?? true
        self.autoLockAfterInactivity = UserDefaults.standard.object(forKey: "autoLockAfterInactivity") as? Bool ?? false
        UserDefaults.standard.register(defaults: [
            "appPIN": "1994",
            "autoLockOnBackground": true,
            "autoLockAfterInactivity": false
        ])
    }
}
