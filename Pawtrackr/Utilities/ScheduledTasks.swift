
import Foundation
import SwiftData

class ScheduledTasks {
    private var timer: Timer?
    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    private let defaults = UserDefaults.standard
    private let lastRunKey = "com.pawtrackr.lastMaintenanceDate"

    func start() {
        timer?.invalidate()
        // Check every hour to see if a new day has passed since the last run.
        timer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
            self?.checkAndRunMaintenance()
        }
        // Run immediately after launch if due.
        checkAndRunMaintenance()
    }

    private func checkAndRunMaintenance() {
        let lastRun = defaults.object(forKey: lastRunKey) as? Date
        if let lastRun, Calendar.current.isDateInToday(lastRun) {
            return
        }
        runMaintenance()
    }

    private func runMaintenance() {
        defaults.set(Date(), forKey: lastRunKey)
        let container = modelContainer
        Task.detached(priority: .background) {
            let context = ModelContext(container)
            SummaryUpdater.rebuildAllSummaries(in: context)
            DataPruner.pruneOldPhotos(olderThan: 180, downsampleOnly: true, in: context)
        }
    }
}
