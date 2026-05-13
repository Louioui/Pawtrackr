
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
        // No periodic in-process Timer: iOS suspends timers when the app
        // backgrounds, so an hourly tick rarely fires for a typical
        // foreground-briefly-then-background usage pattern. The launch-time
        // check below is the real driver. For true background scheduling,
        // migrate to BGAppRefreshTask.
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
        let container = modelContainer
        let defaults = self.defaults
        let lastRunKey = self.lastRunKey
        Task.detached(priority: .background) {
            let context = ModelContext(container)
            SummaryUpdater.rebuildAllSummaries(in: context)
            DataPruner.pruneOldPhotos(olderThan: 180, downsampleOnly: true, in: context)
            // Mark "ran today" only after maintenance succeeded; if the work
            // crashed or threw, we want tomorrow's launch to retry.
            defaults.set(Date(), forKey: lastRunKey)
        }
    }
}
