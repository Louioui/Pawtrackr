
import Foundation
import SwiftData

class ScheduledTasks {
    private var timer: Timer?
    private let modelContainer: ModelContainer
    private let lastPruneKey = "lastPruneRun"

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func start() {
        // Run maintenance daily: summary backfill and conditional pruning.
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: true) { [weak self] _ in
            self?.runBackfill()
            self?.runPruneIfEnabled()
        }
        // Also kick once shortly after launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.runBackfill()
            self?.runPruneIfEnabled()
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

    private func runPruneIfEnabled() {
        // Read pruning threshold from UserDefaults (shared with Settings)
        let thresholdRaw = UserDefaults.standard.string(forKey: "pruningThreshold")
        guard let raw = thresholdRaw, raw != SettingsViewModel.PruningThreshold.never.rawValue else { return }
        // Only prune weekly at most
        let last = UserDefaults.standard.object(forKey: lastPruneKey) as? Date ?? .distantPast
        guard let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: .now), last < oneWeekAgo else { return }

        let cutoff: Date? = {
            switch raw {
            case SettingsViewModel.PruningThreshold.oneYear.rawValue:
                return Calendar.current.date(byAdding: .year, value: -1, to: .now)
            case SettingsViewModel.PruningThreshold.threeYears.rawValue:
                return Calendar.current.date(byAdding: .year, value: -3, to: .now)
            case SettingsViewModel.PruningThreshold.fiveYears.rawValue:
                return Calendar.current.date(byAdding: .year, value: -5, to: .now)
            default: return nil
            }
        }()
        guard let cutoff else { return }

        Task { @MainActor in
            let context = modelContainer.mainContext
            let pruner = DataPruner(modelContext: context)
            try? pruner.pruneVisitPhotos(olderThan: cutoff, keepRecentPhotosPerPet: 2)
            UserDefaults.standard.set(Date(), forKey: lastPruneKey)
        }
    }
}
