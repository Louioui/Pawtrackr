
import Foundation
import SwiftData

class ScheduledTasks {
    private var timer: Timer?
    private let modelContainer: ModelContainer
    private var pruner: DataPruner?

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        self.pruner = DataPruner(modelContainer: modelContainer)
    }

    func start() {
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
        Task {
            // 1. Rebuild summaries for the last 30 days to ensure accuracy
            await MainActor.run {
                let context = modelContainer.mainContext
                SummaryUpdater.rebuildAllSummaries(in: context) // incremental
            }

            // 2. Prune old photos (older than 6 months, keep latest 3 per pet)
            do {
                let sixMonthsAgo = Calendar.current.date(byAdding: .month, value: -6, to: Date()) ?? Date()
                try await pruner?.pruneVisitPhotos(olderThan: sixMonthsAgo, keepRecentPhotosPerPet: 3)
            } catch {
                print("Maintenance error (pruning): \(error)")
            }

            // 3. Compact summaries for the last year
            let cal = Calendar.current
            let yearAgo = cal.date(byAdding: .year, value: -1, to: Date()) ?? Date()
            await pruner?.compactSummaries(in: yearAgo...Date())
        }
    }
}
