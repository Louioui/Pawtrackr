//
//  AppDelegateAdapter.swift
//  Pawtrackr
//
//  Cross-platform AppDelegate hooks. Currently used to:
//  - log the device push token (so silent CloudKit pushes can be delivered)
//  - tell CloudKitMonitor when a remote push wakes the app, so the UI can
//    show "syncing" state during the resulting fetch.
//
//  NSPersistentCloudKitContainer registers its own internal handlers for the
//  CKDatabaseSubscription it creates automatically — we don't need to forward
//  the payload manually. This delegate exists for visibility / observability.
//

import Foundation
import OSLog
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

private let pushLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "Push")

#if canImport(UIKit) && !targetEnvironment(macCatalyst)

final class PawtrackrAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        Task(priority: .background) {
            DataPruningService.shared.performMaintenance()
        }
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        pushLog.info("Registered for remote notifications. Token length: \(deviceToken.count)")
        // Token is forwarded automatically to CloudKit by the system; we just log.
        _ = token
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        pushLog.error("Failed to register for remote notifications: \(error.localizedDescription, privacy: .public)")
    }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        pushLog.info("Received remote notification (likely silent CloudKit push).")
        Task { @MainActor in
            let completed = await CloudKitMonitor.shared.waitForRemoteNotificationSync()
            completionHandler(completed ? .newData : .noData)
        }
    }
}

#elseif canImport(AppKit)

final class PawtrackrAppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        pushLog.info("Registered for remote notifications. Token length: \(deviceToken.count)")
    }

    func application(_ application: NSApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        pushLog.error("Failed to register for remote notifications: \(error.localizedDescription, privacy: .public)")
    }

    func application(_ application: NSApplication,
                     didReceiveRemoteNotification userInfo: [String: Any]) {
        pushLog.info("Received remote notification (likely silent CloudKit push).")
        Task { @MainActor in
            _ = await CloudKitMonitor.shared.waitForRemoteNotificationSync()
        }
    }
}

#endif
