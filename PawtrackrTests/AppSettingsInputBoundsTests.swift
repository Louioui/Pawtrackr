import XCTest

@testable import Pawtrackr

@MainActor
final class AppSettingsInputBoundsTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        resetAppSettingsDefaults()
    }

    override func tearDownWithError() throws {
        resetAppSettingsDefaults()
        try super.tearDownWithError()
    }

    func testSettingsFreeTextValuesClampBeforeDefaultsAndSync() {
        let settings = AppSettings()

        settings.businessName = String(repeating: "Downtown Grooming ", count: 20)
        settings.currencySymbol = String(repeating: "USD", count: 20)
        settings.deviceName = String(repeating: "Front Desk iPad ", count: 20)

        XCTAssertLessThanOrEqual(settings.businessName.count, TextInputLimits.name)
        XCTAssertLessThanOrEqual(settings.currencySymbol.count, 3)
        XCTAssertLessThanOrEqual(settings.deviceName.count, TextInputLimits.shortText)
        XCTAssertLessThanOrEqual(
            UserDefaults.standard.string(forKey: AppSettingsKeys.businessName)?.count ?? 0,
            TextInputLimits.name
        )
        XCTAssertLessThanOrEqual(
            UserDefaults.standard.string(forKey: AppSettingsKeys.deviceName)?.count ?? 0,
            TextInputLimits.shortText
        )
    }

    private func resetAppSettingsDefaults() {
        [
            AppSettingsKeys.businessName,
            AppSettingsKeys.currencySymbol,
            AppSettingsKeys.deviceName,
            AppSettingsKeys.appLanguageOverride,
            AppSettingsKeys.isLockEnabled,
            AppSettingsKeys.isBiometricLockEnabled,
            AppSettingsKeys.autoLockOnBackground,
            AppSettingsKeys.autoLockAfterInactivity,
            AppSettingsKeys.hasSeenAppTour
        ].forEach { key in
            UserDefaults.standard.removeObject(forKey: key)
        }
        KeychainStorage.remove(forKey: AppSettingsKeys.appPINKeychainAccount)
    }
}
