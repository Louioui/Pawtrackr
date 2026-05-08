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

    static var isUITesting: Bool {
        let processInfo = ProcessInfo.processInfo
        return processInfo.arguments.contains(uiTestingArgument)
            || processInfo.environment[uiTestingEnvironmentKey] == "1"
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

    /// True when the host app should keep its persistence in-memory. Both UI
    /// testing (which seeds deterministic data into an in-memory container) and
    /// unit testing (which manages its own container) want this.
    static var prefersInMemoryStore: Bool {
        isUITesting || isRunningTests
    }
}
