//
//  UbiquitousSettingsStore.swift
//  Pawtrackr
//
//  Lightweight iCloud key-value sync for shop-wide identity settings.
//

import Foundation
import OSLog

/// Mirrors a small set of *shop-wide* settings — business name, currency
/// symbol, brand color — through `NSUbiquitousKeyValueStore`.
///
/// This is the fast lane: when the owner renames the business on their Mac,
/// every shop iPad/iPhone picks it up within seconds over iCloud's lightweight
/// key-value channel, without waiting on the heavier SwiftData + CloudKit
/// record sync.
///
/// Per-device preferences (appearance, haptics, auto-lock, PIN, device name)
/// are deliberately NOT mirrored — only shared business identity travels here.
///
/// The `com.apple.developer.ubiquity-kvstore-identifier` entitlement is already
/// present. Without an active iCloud account the calls degrade to a local-only
/// store — no crash, just no cross-device propagation.
@MainActor
final class UbiquitousSettingsStore {
    static let shared = UbiquitousSettingsStore()

    /// Keys mirrored to iCloud. Values intentionally match `AppSettingsKeys`.
    nonisolated static let syncedKeys: Set<String> = [
        AppSettingsKeys.businessName,
        AppSettingsKeys.currencySymbol,
        AppSettingsKeys.brandColorHex
    ]

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr",
                                category: "SettingsSync")
    private weak var appSettings: AppSettings?
    private var observer: NSObjectProtocol?

    private init() {}

    /// Begins observing external iCloud changes. Call once, right after
    /// `AppSettings` is constructed. On first run it reconciles local and
    /// iCloud values: an existing iCloud value wins; otherwise the local
    /// value is published upward.
    func start(appSettings: AppSettings) {
        guard observer == nil else { return }
        guard AppRuntime.allowsICloudSync else {
            logger.debug("Skipping iCloud settings sync for this runtime.")
            return
        }
        self.appSettings = appSettings

        let store = NSUbiquitousKeyValueStore.default
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: .main
        ) { [weak self] note in
            let keys = (note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]) ?? []
            Task { @MainActor in self?.adopt(changedKeys: keys) }
        }

        store.synchronize()
        reconcileOnLaunch()
    }

    /// Pushes a setting value up to iCloud. Called from `AppSettings` didSet.
    /// Non-synced keys are ignored, so callers need not pre-filter.
    nonisolated func push(_ value: String, forKey key: String) {
        guard Self.syncedKeys.contains(key) else { return }
        guard AppRuntime.allowsICloudSync else { return }
        NSUbiquitousKeyValueStore.default.set(value, forKey: key)
    }

    /// First-launch reconciliation: adopt any value iCloud already holds,
    /// otherwise seed iCloud from the local value.
    private func reconcileOnLaunch() {
        let store = NSUbiquitousKeyValueStore.default
        for key in Self.syncedKeys {
            if let remote = store.string(forKey: key) {
                apply(value: remote, forKey: key)
            } else if let local = UserDefaults.standard.string(forKey: key) {
                store.set(local, forKey: key)
            }
        }
    }

    /// Applies inbound iCloud changes to `AppSettings`.
    private func adopt(changedKeys: [String]) {
        let store = NSUbiquitousKeyValueStore.default
        for key in changedKeys where Self.syncedKeys.contains(key) {
            guard let value = store.string(forKey: key) else { continue }
            apply(value: value, forKey: key)
            logger.info("Adopted iCloud settings change for \(key, privacy: .public)")
        }
    }

    /// Writes a value into `AppSettings`. The equality guards stop redundant
    /// `didSet` churn and prevent the change from echoing back to iCloud.
    private func apply(value: String, forKey key: String) {
        guard let settings = appSettings else { return }
        switch key {
        case AppSettingsKeys.businessName where settings.businessName != value:
            settings.businessName = value
        case AppSettingsKeys.currencySymbol where settings.currencySymbol != value:
            settings.currencySymbol = value
        case AppSettingsKeys.brandColorHex where settings.brandColorHex != value:
            settings.brandColorHex = value
        default:
            break
        }
    }
}
