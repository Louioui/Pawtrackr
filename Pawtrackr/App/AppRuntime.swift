//
//  AppRuntime.swift
//  Pawtrackr
//
//  Process-level runtime switches for deterministic test launches.
//

import Foundation

enum AppRuntime {
    static let uiTestingArgument = "-pawtrackr-ui-testing"
    static let uiTestingEnvironmentKey = "PAWTRACKR_UI_TESTING"
    static let uiTestingStartTabEnvironmentKey = "PAWTRACKR_UI_START_TAB"
    static let inMemoryStoreEnvironmentKey = "PAWTRACKR_IN_MEMORY_STORE"
    /// When set, the UI test seeder will skip inserting a BusinessConfig so the
    /// onboarding flow shows on launch — used to drive onboarding XCUI tests.
    static let onboardingTestArgument = "-pawtrackr-ui-onboarding"

    static var isUITesting: Bool {
        let processInfo = ProcessInfo.processInfo
        return processInfo.arguments.contains(uiTestingArgument)
            || processInfo.environment[uiTestingEnvironmentKey] == "1"
    }

    /// True when the UI tester wants the onboarding flow to be shown on launch.
    static var isOnboardingTestMode: Bool {
        ProcessInfo.processInfo.arguments.contains(onboardingTestArgument)
    }

    static var uiTestingStartTab: String? {
        guard isUITesting else { return nil }
        return ProcessInfo.processInfo.environment[uiTestingStartTabEnvironmentKey]?.lowercased()
    }

    /// True when the process was launched by XCTest (unit or UI test). Used by
    /// PawtrackrApp to avoid opening the production CloudKit-backed disk store
    /// during tests, which otherwise registers a second SwiftData store and can
    /// invalidate model instances created in a test's in-memory container.
    static var isRunningTests: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["XCTestConfigurationFilePath"] != nil
            || env["XCTestBundlePath"] != nil
            || NSClassFromString("XCTest") != nil
    }

    /// True when the host app should keep persistence in-memory instead of
    /// opening the production CloudKit-backed disk store.
    static var prefersInMemoryStore: Bool {
        let env = ProcessInfo.processInfo.environment
        return isUITesting
            || env[inMemoryStoreEnvironmentKey] == "1"
    }

    /// Current UI-test launch scenario (e.g. "empty", "loaded", "error").
    static var currentScenario: Scenario {
        let raw = ProcessInfo.processInfo.environment["PAWTRACKR_SCENARIO"] ?? ""
        return Scenario(rawValue: raw) ?? .default
    }

    enum Scenario: String {
        case `default` = ""
        case empty
        case heavyLoad = "heavy_load"
        case syncError = "sync_error"
    }
}
