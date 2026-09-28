//
//  AppLockProtectionStatusTests.swift
//  PawtrackrTests
//
//  Regression: after a device-backup restore, UserDefaults brings back
//  `isLockEnabled` but the ThisDeviceOnly Keychain PIN does not. The Security
//  card used to say "PIN set" with a green shield while the app opened
//  unlocked.
//

import XCTest
@testable import Pawtrackr

final class AppLockProtectionStatusTests: XCTestCase {
    func testLockEnabledWithoutPINIsNotProtected() {
        let status = AppLockProtectionStatus.resolve(isLockEnabled: true, isPINSet: false, isBiometricLockEnabled: true)
        XCTAssertEqual(status, .needsPIN)
        XCTAssertFalse(status.isProtected)
    }

    func testLockEnabledWithPINIsProtected() {
        XCTAssertEqual(
            AppLockProtectionStatus.resolve(isLockEnabled: true, isPINSet: true, isBiometricLockEnabled: false),
            .protected(biometric: false)
        )
        XCTAssertEqual(
            AppLockProtectionStatus.resolve(isLockEnabled: true, isPINSet: true, isBiometricLockEnabled: true),
            .protected(biometric: true)
        )
        XCTAssertTrue(AppLockProtectionStatus.protected(biometric: false).isProtected)
    }

    func testLockDisabledIsOffWhateverThePIN() {
        XCTAssertEqual(AppLockProtectionStatus.resolve(isLockEnabled: false, isPINSet: true, isBiometricLockEnabled: true), .off)
        XCTAssertEqual(AppLockProtectionStatus.resolve(isLockEnabled: false, isPINSet: false, isBiometricLockEnabled: false), .off)
        XCTAssertFalse(AppLockProtectionStatus.off.isProtected)
    }
}
