import Foundation
import SwiftData
import CoreData
import Combine
import SwiftUI

@Observable
final class ShopSyncCoordinator {
    static let shared = ShopSyncCoordinator()
    
    var activeContainer: ModelContainer?
    var isSyncingActive: Bool = false
    private var syncObservers = Set<AnyCancellable>()
    
    init() {
        setupCloudKitNotificationWatcher()
    }
    
    func configureEcosystemContainer(with container: ModelContainer) {
        self.activeContainer = container
    }
    
    private func setupCloudKitNotificationWatcher() {
        NotificationCenter.default
            .publisher(for: .NSPersistentStoreRemoteChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.forceSynchronousUIRefresh()
                }
            }
            .store(in: &syncObservers)
    }
    
    @MainActor
    private func forceSynchronousUIRefresh() {
        guard let context = activeContainer?.mainContext else { return }
        isSyncingActive = true
        context.processPendingChanges()
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            await MainActor.run {
                self.isSyncingActive = false
            }
        }
    }
}
