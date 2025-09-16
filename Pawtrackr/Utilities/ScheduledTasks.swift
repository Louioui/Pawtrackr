
import Foundation
import SwiftData

class ScheduledTasks {
    private var timer: Timer?
    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func start() {
        // Run the backfill task every 24 hours.
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: true) { [weak self] _ in
            self?.runBackfill()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func runBackfill() {
        Task {
            await MainActor.run {
                let context = modelContainer.mainContext
                DataMigrations.backfillDaySummaries(in: context)
            }
        }
    }
}
