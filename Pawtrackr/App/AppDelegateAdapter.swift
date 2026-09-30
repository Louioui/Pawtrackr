//
//  AppDelegateAdapter.swift
//  Pawtrackr
//
//  Cross-platform lifecycle hooks for local maintenance and Dock re-opening.
//

import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

#if canImport(UIKit) && !targetEnvironment(macCatalyst)

final class PawtrackrAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        Task(priority: .background) {
            DataPruningService.shared.performMaintenance()
        }
        return true
    }
}

#elseif canImport(AppKit)

final class PawtrackrAppDelegate: NSObject, NSApplicationDelegate {
    /// Dock re-open support for the menu-bar-extra lifecycle. If the main
    /// window has been closed while the app remains alive, a Dock click must
    /// bring Pawtrackr back onscreen instead of leaving only the menu bar item.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            if let window = sender.windows.first(where: { $0.canBecomeMain }) {
                window.makeKeyAndOrderFront(self)
            }
            NSApp.activate(ignoringOtherApps: true)
        }
        return true
    }
}

#endif
