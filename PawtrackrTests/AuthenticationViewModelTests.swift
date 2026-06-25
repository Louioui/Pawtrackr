//
//  AuthenticationViewModelTests.swift
//  PawtrackrTests
//
//  Baseline coverage for AuthenticationViewModel: PIN sign-in success
//  and failure, sign-out, idempotent local-user creation, and the
//  resilience contract that all methods are no-ops when the model
//  context is unavailable (recovery-mode launches).
//

import XCTest
import SwiftData
@testable import Pawtrackr

@MainActor
final class AuthenticationViewModelTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var settings: AppSettings!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let schema = Schema(PawtrackrSchema.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [config])
        context = container.mainContext
        settings = AppSettings()
        settings.changePIN(to: "4242")
    }

    override func tearDownWithError() throws {
        container = nil
        context = nil
        settings = nil
        try super.tearDownWithError()
    }

    func testInitialState_NotAuthenticated() {
        let vm = AuthenticationViewModel(modelContext: context)
        XCTAssertFalse(vm.isAuthenticated)
        XCTAssertNil(vm.currentUser)
    }

    func testNoFallbackPIN_LockCannotValidateWithoutRealPIN() {
        // Security regression: the app must NOT fall back to a compiled-in PIN.
        // With no Keychain PIN, isPINSet is false and no code (including the
        // formerly-default "1994"/"0000") can validate or arm the lock.
        KeychainStorage.remove(forKey: AppSettingsKeys.appPINKeychainAccount)
        let freshSettings = AppSettings()
        XCTAssertFalse(freshSettings.isPINSet, "A fresh install with no stored PIN must report no PIN set.")
        XCTAssertTrue(freshSettings.appPIN.isEmpty, "appPIN must stay empty when no real PIN is stored.")
        XCTAssertFalse(freshSettings.validatePIN("1994"), "The leaked default PIN must never unlock the app.")
        XCTAssertFalse(freshSettings.validatePIN("0000"), "No compiled-in fallback PIN may unlock the app.")
    }

    func testSetPIN_EnablesValidationAndMarksPINSet() {
        KeychainStorage.remove(forKey: AppSettingsKeys.appPINKeychainAccount)
        let freshSettings = AppSettings()
        XCTAssertTrue(freshSettings.changePIN(to: "7531"))
        XCTAssertTrue(freshSettings.isPINSet)
        XCTAssertTrue(freshSettings.validatePIN("7531"))
        XCTAssertFalse(freshSettings.validatePIN("1994"))
    }

    func testSignInWithPIN_RejectsWrongPIN() {
        let vm = AuthenticationViewModel(modelContext: context)
        let ok = vm.signInWithPIN("0000", appSettings: settings)
        XCTAssertFalse(ok, "Wrong PIN should not authenticate.")
        XCTAssertFalse(vm.isAuthenticated)
        XCTAssertNil(vm.currentUser)
    }

    func testSignInWithPIN_AcceptsCorrectPIN() {
        let vm = AuthenticationViewModel(modelContext: context)
        let ok = vm.signInWithPIN("4242", appSettings: settings)
        XCTAssertTrue(ok)
        XCTAssertTrue(vm.isAuthenticated)
        XCTAssertNotNil(vm.currentUser)
    }

    func testSignInWithPIN_IsIdempotent_DoesNotCreateDuplicateUsers() throws {
        let vm = AuthenticationViewModel(modelContext: context)
        _ = vm.signInWithPIN("4242", appSettings: settings)
        _ = vm.signInWithPIN("4242", appSettings: settings)
        _ = vm.signInWithPIN("4242", appSettings: settings)

        let users = try context.fetch(FetchDescriptor<User>())
        XCTAssertEqual(users.count, 1, "Repeated sign-ins must reuse the existing local user, not insert a new one each time.")
    }

    func testSignOut_ClearsState() {
        let vm = AuthenticationViewModel(modelContext: context)
        _ = vm.signInWithPIN("4242", appSettings: settings)
        XCTAssertTrue(vm.isAuthenticated)

        vm.signOut()
        XCTAssertFalse(vm.isAuthenticated)
        XCTAssertNil(vm.currentUser)
    }

    func testSignInAfterPINValidation_AssumesCallerAlreadyValidated() {
        // signInAfterPINValidation skips PIN check — callers (PinLockView)
        // are expected to validate first. The contract is "if you call this,
        // you've already verified the PIN."
        let vm = AuthenticationViewModel(modelContext: context)
        vm.signInAfterPINValidation()
        XCTAssertTrue(vm.isAuthenticated, "Method's contract is to authenticate without re-checking PIN.")
        XCTAssertNotNil(vm.currentUser)
    }

    func testNilContext_AllMethodsAreNoOp() {
        // When the data store fails to open we hand the VM a nil context.
        // Every method must remain a no-op rather than crashing.
        let vm = AuthenticationViewModel(modelContext: nil)
        let ok = vm.signInWithPIN("4242", appSettings: settings)
        XCTAssertFalse(ok, "Without a context there's no User table — sign-in cannot succeed.")
        vm.signInAfterPINValidation()  // must not crash
        vm.signInAfterUnlock()         // must not crash
        vm.signIn(email: "x@y.z")      // must not crash
        XCTAssertFalse(vm.isAuthenticated)
    }

    // MARK: - PIN format validation (AppSettings level)

    func testIsValidPIN_RejectsNonNumeric() {
        XCTAssertFalse(AppSettings.isValidPIN("12a4"))
        XCTAssertFalse(AppSettings.isValidPIN("    "))
        XCTAssertFalse(AppSettings.isValidPIN("    "))
    }

    func testIsValidPIN_RejectsWrongLength() {
        XCTAssertFalse(AppSettings.isValidPIN("123"))
        XCTAssertFalse(AppSettings.isValidPIN("12345"))
        XCTAssertFalse(AppSettings.isValidPIN(""))
    }

    func testIsValidPIN_AcceptsExactlyFourDigits() {
        XCTAssertTrue(AppSettings.isValidPIN("0000"))
        XCTAssertTrue(AppSettings.isValidPIN("9999"))
        XCTAssertTrue(AppSettings.isValidPIN("1234"))
    }
}
