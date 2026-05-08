
import Foundation
import SwiftData

class ScheduledTasks {
    private var timer: Timer?
    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func start() {
        // Invalidate any pre-existing timer to avoid orphaning it if start() is
        // called more than once for the same instance.
        timer?.invalidate()
        // Run maintenance daily.
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: true) { [weak self] _ in
            self?.runMaintenance()
        }
        // Also kick once shortly after launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.runMaintenance()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    deinit {
        stop()
    }

    private func runMaintenance() {
        let container = modelContainer
        Task.detached(priority: .background) {
            let context = ModelContext(container)
            // 1. Incremental summary rebuild for changed days.
            SummaryUpdater.rebuildAllSummaries(in: context)
            // 2. Prune/downsample old photos (older than 6 months).
            DataPruner.pruneOldPhotos(olderThan: 180, downsampleOnly: true, in: context)
        }
    }
}
