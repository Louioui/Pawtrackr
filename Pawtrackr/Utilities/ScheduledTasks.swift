
import Foundation
import SwiftData

class ScheduledTasks {
    private var timer: Timer?
    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func start() {
        // Run maintenance daily: summary backfill.
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: true) { [weak self] _ in
            self?.runBackfill()
        }
        // Also kick once shortly after launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.runBackfill()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    deinit {
        stop()
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
