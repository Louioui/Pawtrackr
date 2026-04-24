//
//  AppSettings.swift
//  Pawtrackr
//
//  User preferences and security settings.
//

import SwiftUI
import Combine

final class AppSettings: ObservableObject {
    // MARK: - Keys

    private enum Keys {
        static let biometricLockEnabled = "isBiometricLockEnabled"
        static let appPIN = "appPIN"
        static let lastPINChangeDate = "lastPINChangeDate"
        static let autoLockOnBackground = "autoLockOnBackground"
        static let autoLockAfterInactivity = "autoLockAfterInactivity"
        static let businessName = "businessName"
        static let currencySymbol = "currencySymbol"
    }

    // MARK: - Defaults

    private enum Defaults {
        static let pin = "1994"
        static let biometricEnabled = true
        static let autoLockBackground = true
        static let autoLockInactivity = false
        static let idleLockMinutes = 5
        static let businessName = "My Pet Grooming"
        static let currencySymbol = "$"
    }

    // MARK: - Published Properties

    @Published var businessName: String {
        didSet {
            UserDefaults.standard.set(businessName, forKey: Keys.businessName)
        }
    }

    @Published var currencySymbol: String {
        didSet {
            UserDefaults.standard.set(currencySymbol, forKey: Keys.currencySymbol)
        }
    }

    @Published var isBiometricLockEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isBiometricLockEnabled, forKey: Keys.biometricLockEnabled)
        }
    }

    /// 4-digit App PIN. Validated to ensure it's exactly 4 digits.
    @Published private(set) var appPIN: String {
        didSet {
            UserDefaults.standard.set(appPIN, forKey: Keys.appPIN)
        }
    }

    @Published var lastPINChangeDate: Date? {
        didSet {
            if let d = lastPINChangeDate {
                UserDefaults.standard.set(d, forKey: Keys.lastPINChangeDate)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.lastPINChangeDate)
            }
        }
    }

    @Published var autoLockOnBackground: Bool {
        didSet {
            UserDefaults.standard.set(autoLockOnBackground, forKey: Keys.autoLockOnBackground)
        }
    }

    @Published var autoLockAfterInactivity: Bool {
        didSet {
            UserDefaults.standard.set(autoLockAfterInactivity, forKey: Keys.autoLockAfterInactivity)
        }
    }

    /// Fixed idle threshold (minutes) for auto-lock.
    let idleLockMinutes: Int = Defaults.idleLockMinutes

    // MARK: - Init

    init() {
        // Register defaults first
        UserDefaults.standard.register(defaults: [
            Keys.biometricLockEnabled: Defaults.biometricEnabled,
            Keys.appPIN: Defaults.pin,
            Keys.autoLockOnBackground: Defaults.autoLockBackground,
            Keys.autoLockAfterInactivity: Defaults.autoLockInactivity
        ])

        // Read values
        self.businessName = UserDefaults.standard.string(forKey: Keys.businessName) ?? Defaults.businessName
        self.currencySymbol = UserDefaults.standard.string(forKey: Keys.currencySymbol) ?? Defaults.currencySymbol
        self.isBiometricLockEnabled = UserDefaults.standard.bool(forKey: Keys.biometricLockEnabled)
        self.autoLockOnBackground = UserDefaults.standard.bool(forKey: Keys.autoLockOnBackground)
        self.autoLockAfterInactivity = UserDefaults.standard.bool(forKey: Keys.autoLockAfterInactivity)
        self.lastPINChangeDate = UserDefaults.standard.object(forKey: Keys.lastPINChangeDate) as? Date

        // Validate stored PIN
        let storedPIN = UserDefaults.standard.string(forKey: Keys.appPIN) ?? Defaults.pin
        self.appPIN = Self.isValidPIN(storedPIN) ? storedPIN : Defaults.pin
    }

    // MARK: - PIN Management

    /// Changes the PIN after validating it's exactly 4 digits.
    /// Returns true if the PIN was successfully changed.
    @discardableResult
    func changePIN(to newPIN: String) -> Bool {
        guard Self.isValidPIN(newPIN) else { return false }
        appPIN = newPIN
        lastPINChangeDate = Date()
        return true
    }

    /// Validates the provided PIN against the stored PIN.
    func validatePIN(_ pin: String) -> Bool {
        pin == appPIN
    }

    /// Resets PIN to default value.
    func resetPINToDefault() {
        appPIN = Defaults.pin
        lastPINChangeDate = Date()
    }

    /// Checks if a PIN is valid (exactly 4 numeric digits).
    static func isValidPIN(_ pin: String) -> Bool {
        pin.count == 4 && pin.allSatisfy { $0.isNumber }
    }
}
