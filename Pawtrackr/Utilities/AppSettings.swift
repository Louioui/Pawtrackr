//
//  AppSettings.swift
//  Pawtrackr
//
//  User preferences and security settings.
//

import SwiftUI
import Observation

/// Keys used for UserDefaults persistence.
/// Internal visibility ensures accessibility for Observation macro expansion across platforms.
enum AppSettingsKeys {
    static let isLockEnabled = "isLockEnabled"
    static let isBiometricLockEnabled = "isBiometricLockEnabled"
    /// Legacy UserDefaults key — kept only so we can migrate any existing
    /// plaintext PIN out of UserDefaults and into the Keychain on launch,
    /// then erase it. New writes should never set this key.
    static let legacyAppPIN = "appPIN"
    /// Keychain account name for the current PIN.
    static let appPINKeychainAccount = "appPIN"
    static let lastPINChangeDate = "lastPINChangeDate"
    static let autoLockOnBackground = "autoLockOnBackground"
    static let autoLockAfterInactivity = "autoLockAfterInactivity"
    static let businessName = "businessName"
    static let currencySymbol = "currencySymbol"
    static let hasConfiguredPrices = "hasConfiguredPrices"
    static let hasAddedFirstClient = "hasAddedFirstClient"
    static let hasCompletedFirstVisit = "hasCompletedFirstVisit"
    static let isChecklistDismissed = "isChecklistDismissed"
    static let hasSeenAppTour = "hasSeenAppTour"
    static let preferredColorScheme = "preferredColorScheme"
    static let hapticsEnabled = "hapticsEnabled"
    static let brandColorHex = "brandColorHex"
    static let defaultLaunchTab = "defaultLaunchTab"
}

/// User-selectable color scheme preference. `system` defers to the OS.
enum AppColorScheme: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return NSLocalizedString("settings.appearance.system", value: "Follow System", comment: "")
        case .light:  return NSLocalizedString("settings.appearance.light",  value: "Light",         comment: "")
        case .dark:   return NSLocalizedString("settings.appearance.dark",   value: "Dark",          comment: "")
        }
    }

    var swiftUIScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

@Observable
final class AppSettings {
    // MARK: - Defaults

    private enum Defaults {
        static let isLockEnabled = true
        static let pin = "1994"
        static let biometricEnabled = true
        static let autoLockBackground = true
        static let autoLockInactivity = false
        static let idleLockMinutes = 5
        static let businessName = "My Pet Grooming"
        static let currencySymbol = "$"
        static let hasConfiguredPrices = false
        static let hasAddedFirstClient = false
        static let hasCompletedFirstVisit = false
        static let isChecklistDismissed = false
        static let preferredColorScheme = AppColorScheme.system.rawValue
        static let hapticsEnabled = true
        static let brandColorHex = "#6366F1"
        static let defaultLaunchTab = "dashboard"
    }

    // MARK: - Properties

    var hasConfiguredPrices: Bool {
        didSet { UserDefaults.standard.set(hasConfiguredPrices, forKey: AppSettingsKeys.hasConfiguredPrices) }
    }
    
    var hasAddedFirstClient: Bool {
        didSet { UserDefaults.standard.set(hasAddedFirstClient, forKey: AppSettingsKeys.hasAddedFirstClient) }
    }
    
    var hasCompletedFirstVisit: Bool {
        didSet { UserDefaults.standard.set(hasCompletedFirstVisit, forKey: AppSettingsKeys.hasCompletedFirstVisit) }
    }
    
    var isChecklistDismissed: Bool {
        didSet { UserDefaults.standard.set(isChecklistDismissed, forKey: AppSettingsKeys.isChecklistDismissed) }
    }

    /// True once the new-user feature tour has been seen (or explicitly skipped).
    /// Defaults to `false` so a fresh install gets the tour after onboarding.
    var hasSeenAppTour: Bool {
        didSet { UserDefaults.standard.set(hasSeenAppTour, forKey: AppSettingsKeys.hasSeenAppTour) }
    }

    var businessName: String {
        didSet {
            UserDefaults.standard.set(businessName, forKey: AppSettingsKeys.businessName)
        }
    }

    var currencySymbol: String {
        didSet {
            UserDefaults.standard.set(currencySymbol, forKey: AppSettingsKeys.currencySymbol)
        }
    }

    var isLockEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isLockEnabled, forKey: AppSettingsKeys.isLockEnabled)
        }
    }

    var isBiometricLockEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isBiometricLockEnabled, forKey: AppSettingsKeys.isBiometricLockEnabled)
        }
    }

    /// 4-digit App PIN. Validated to ensure it's exactly 4 digits.
    /// Backed by the Keychain (kSecAttrAccessibleWhenUnlockedThisDeviceOnly)
    /// instead of UserDefaults, so it's not in plaintext device backups.
    private(set) var appPIN: String {
        didSet {
            KeychainStorage.set(appPIN, forKey: AppSettingsKeys.appPINKeychainAccount)
        }
    }

    var lastPINChangeDate: Date? {
        didSet {
            if let d = lastPINChangeDate {
                UserDefaults.standard.set(d, forKey: AppSettingsKeys.lastPINChangeDate)
            } else {
                UserDefaults.standard.removeObject(forKey: AppSettingsKeys.lastPINChangeDate)
            }
        }
    }

    var autoLockOnBackground: Bool {
        didSet {
            UserDefaults.standard.set(autoLockOnBackground, forKey: AppSettingsKeys.autoLockOnBackground)
        }
    }

    var autoLockAfterInactivity: Bool {
        didSet {
            UserDefaults.standard.set(autoLockAfterInactivity, forKey: AppSettingsKeys.autoLockAfterInactivity)
        }
    }

    /// User-selected appearance. The SettingsView surfaces this; ContentView
    /// applies it via `.preferredColorScheme(...)` so the whole tree responds.
    var preferredColorScheme: AppColorScheme {
        didSet {
            UserDefaults.standard.set(preferredColorScheme.rawValue, forKey: AppSettingsKeys.preferredColorScheme)
        }
    }

    /// Global haptics toggle. `HapticManager` reads this on each call so any
    /// view that triggers feedback (buttons, toggles, etc.) is silenced when
    /// disabled — no per-callsite changes required.
    var hapticsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(hapticsEnabled, forKey: AppSettingsKeys.hapticsEnabled)
        }
    }

    /// Persisted accent color (`#RRGGBB`) for `DS.ColorToken.primary`.
    /// The didSet pushes the value into `ThemeManager` so existing views
    /// using `DS.ColorToken.primary` recolor live without a relaunch.
    var brandColorHex: String {
        didSet {
            UserDefaults.standard.set(brandColorHex, forKey: AppSettingsKeys.brandColorHex)
            ThemeManager.shared.updateBrandColor(hex: brandColorHex)
        }
    }

    /// Which tab to open on cold launch. Stored as the `NavigationItem` raw
    /// value (e.g. "dashboard", "clients", "insights", "settings"). UI tests
    /// override this via `applyUITestLaunchOverrides()`.
    var defaultLaunchTab: String {
        didSet {
            UserDefaults.standard.set(defaultLaunchTab, forKey: AppSettingsKeys.defaultLaunchTab)
        }
    }

    /// Fixed idle threshold (minutes) for auto-lock.
    let idleLockMinutes: Int = Defaults.idleLockMinutes

    // MARK: - Init

    init() {
        if AppRuntime.isUITesting {
            UserDefaults.standard.set(false, forKey: AppSettingsKeys.isLockEnabled)
            UserDefaults.standard.set(false, forKey: AppSettingsKeys.isBiometricLockEnabled)
            UserDefaults.standard.set(false, forKey: AppSettingsKeys.autoLockOnBackground)
            UserDefaults.standard.set(false, forKey: AppSettingsKeys.autoLockAfterInactivity)
            UserDefaults.standard.set(Defaults.currencySymbol, forKey: AppSettingsKeys.currencySymbol)
        }

        // Register defaults first
        // hasSeenAppTour defaults to TRUE so existing installs (which never
        // explicitly set the key) don't suddenly see the tour on update.
        // OnboardingViewModel writes `false` after a fresh setup completes,
        // which is the only path that arms the tour.
        UserDefaults.standard.register(defaults: [
            AppSettingsKeys.isLockEnabled: AppRuntime.isUITesting ? false : Defaults.isLockEnabled,
            AppSettingsKeys.isBiometricLockEnabled: AppRuntime.isUITesting ? false : Defaults.biometricEnabled,
            AppSettingsKeys.autoLockOnBackground: AppRuntime.isUITesting ? false : Defaults.autoLockBackground,
            AppSettingsKeys.autoLockAfterInactivity: AppRuntime.isUITesting ? false : Defaults.autoLockInactivity,
            AppSettingsKeys.hasConfiguredPrices: Defaults.hasConfiguredPrices,
            AppSettingsKeys.hasAddedFirstClient: Defaults.hasAddedFirstClient,
            AppSettingsKeys.hasCompletedFirstVisit: Defaults.hasCompletedFirstVisit,
            AppSettingsKeys.isChecklistDismissed: Defaults.isChecklistDismissed,
            AppSettingsKeys.hasSeenAppTour: true,
            AppSettingsKeys.preferredColorScheme: Defaults.preferredColorScheme,
            AppSettingsKeys.hapticsEnabled: Defaults.hapticsEnabled,
            AppSettingsKeys.brandColorHex: Defaults.brandColorHex,
            AppSettingsKeys.defaultLaunchTab: Defaults.defaultLaunchTab
        ])

        // Read values
        self.businessName = UserDefaults.standard.string(forKey: AppSettingsKeys.businessName) ?? Defaults.businessName
        self.currencySymbol = UserDefaults.standard.string(forKey: AppSettingsKeys.currencySymbol) ?? Defaults.currencySymbol
        self.isLockEnabled = UserDefaults.standard.bool(forKey: AppSettingsKeys.isLockEnabled)
        self.isBiometricLockEnabled = UserDefaults.standard.bool(forKey: AppSettingsKeys.isBiometricLockEnabled)
        self.autoLockOnBackground = UserDefaults.standard.bool(forKey: AppSettingsKeys.autoLockOnBackground)
        self.autoLockAfterInactivity = UserDefaults.standard.bool(forKey: AppSettingsKeys.autoLockAfterInactivity)
        self.lastPINChangeDate = UserDefaults.standard.object(forKey: AppSettingsKeys.lastPINChangeDate) as? Date

        self.hasConfiguredPrices = UserDefaults.standard.bool(forKey: AppSettingsKeys.hasConfiguredPrices)
        self.hasAddedFirstClient = UserDefaults.standard.bool(forKey: AppSettingsKeys.hasAddedFirstClient)
        self.hasCompletedFirstVisit = UserDefaults.standard.bool(forKey: AppSettingsKeys.hasCompletedFirstVisit)
        self.isChecklistDismissed = UserDefaults.standard.bool(forKey: AppSettingsKeys.isChecklistDismissed)
        self.hasSeenAppTour = UserDefaults.standard.bool(forKey: AppSettingsKeys.hasSeenAppTour)

        let storedSchemeRaw = UserDefaults.standard.string(forKey: AppSettingsKeys.preferredColorScheme) ?? Defaults.preferredColorScheme
        self.preferredColorScheme = AppColorScheme(rawValue: storedSchemeRaw) ?? .system
        self.hapticsEnabled = UserDefaults.standard.bool(forKey: AppSettingsKeys.hapticsEnabled)
        self.brandColorHex = UserDefaults.standard.string(forKey: AppSettingsKeys.brandColorHex) ?? Defaults.brandColorHex
        self.defaultLaunchTab = UserDefaults.standard.string(forKey: AppSettingsKeys.defaultLaunchTab) ?? Defaults.defaultLaunchTab

        // Migrate any existing plaintext PIN out of UserDefaults into the
        // Keychain, then erase the UserDefaults copy. Future reads come from
        // the Keychain only.
        let legacyPIN = UserDefaults.standard.string(forKey: AppSettingsKeys.legacyAppPIN)
        if let legacy = legacyPIN, Self.isValidPIN(legacy),
           KeychainStorage.string(forKey: AppSettingsKeys.appPINKeychainAccount) == nil {
            KeychainStorage.set(legacy, forKey: AppSettingsKeys.appPINKeychainAccount)
        }
        if legacyPIN != nil {
            UserDefaults.standard.removeObject(forKey: AppSettingsKeys.legacyAppPIN)
        }

        let storedPIN = KeychainStorage.string(forKey: AppSettingsKeys.appPINKeychainAccount) ?? Defaults.pin
        self.appPIN = Self.isValidPIN(storedPIN) ? storedPIN : Defaults.pin
        // If we just defaulted (no Keychain entry yet, no legacy migration),
        // make sure the Keychain has a value so subsequent reads are stable.
        if KeychainStorage.string(forKey: AppSettingsKeys.appPINKeychainAccount) == nil {
            KeychainStorage.set(self.appPIN, forKey: AppSettingsKeys.appPINKeychainAccount)
        }

        // Apply saved accent color to ThemeManager so views using
        // DS.ColorToken.primary render with it from the first frame.
        ThemeManager.shared.updateBrandColor(hex: brandColorHex)
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
