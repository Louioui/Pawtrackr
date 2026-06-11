import Foundation
import SwiftData

@Observable
final class ShopSyncCoordinator {
    static let shared = ShopSyncCoordinator()
    
    var activeContainer: ModelContainer?
    var isSyncingActive: Bool = false
    
    init() {}
    
    func configureEcosystemContainer(with container: ModelContainer) {
        self.activeContainer = container
    }
}
