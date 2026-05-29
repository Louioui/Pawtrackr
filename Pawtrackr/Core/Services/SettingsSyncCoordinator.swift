import Foundation
import Combine

/// A coordinator that synchronizes application settings across devices using NSUbiquitousKeyValueStore.
@MainActor
final class SettingsSyncCoordinator {
    static let shared = SettingsSyncCoordinator()
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didChangeExternally),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default
        )
    }
    
    @objc private func didChangeExternally(notification: Notification) {
        // Handle synchronization of settings from external sources (other devices).
        // The NSUbiquitousKeyValueStore will automatically update local values.
        // We can trigger an event or refresh settings here if needed.
    }
    
    func synchronize() {
        NSUbiquitousKeyValueStore.default.synchronize()
    }
}
