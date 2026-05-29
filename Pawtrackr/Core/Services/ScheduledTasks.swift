
import Foundation
import SwiftData
import OSLog
#if canImport(BackgroundTasks)
import BackgroundTasks
#endif

class ScheduledTasks {
    static let maintenanceTaskIdentifier = "PartnerShipWithMedia.Pawtrackr.maintenance"

    private let modelContainer: ModelContainer
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "ScheduledTasks")

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    private let defaults = UserDefaults.standard
    private let lastRunKey = "com.pawtrackr.lastMaintenanceDate"

    func start() {
        registerBackgroundMaintenance()
        checkAndRunMaintenance()
        scheduleBackgroundMaintenance()
    }

    private func checkAndRunMaintenance() {
        let lastRun = defaults.object(forKey: lastRunKey) as? Date
        guard shouldRunMaintenance(lastRun: lastRun, now: Date()) else { return }
        runMaintenance(reason: "launch fallback")
    }

    private func runMaintenance(reason: String) {
        let container = modelContainer
        let defaults = self.defaults
        let lastRunKey = self.lastRunKey
        let log = self.log
        Task.detached(priority: .background) {
            let success = Self.performMaintenance(
                container: container,
                defaults: defaults,
                lastRunKey: lastRunKey,
                log: log,
                reason: reason
            )
            if !success {
                log.error("Maintenance did not complete for reason=\(reason, privacy: .public)")
            }
        }
    }

    private static func performMaintenance(
        container: ModelContainer,
        defaults: UserDefaults,
        lastRunKey: String,
        log: Logger,
        reason: String
    ) -> Bool {
        if Task.isCancelled { return false }

        log.info("Starting maintenance: \(reason, privacy: .public)")
        let context = ModelContext(container)
        SummaryUpdater.rebuildAllSummaries(in: context)
        if Task.isCancelled { return false }

        DataPruner.pruneOldPhotos(olderThan: 180, downsampleOnly: true, in: context)
        if Task.isCancelled { return false }

        defaults.set(Date(), forKey: lastRunKey)
        log.info("Completed maintenance: \(reason, privacy: .public)")
        return true
    }

    private func shouldRunMaintenance(lastRun: Date?, now: Date) -> Bool {
        let calendar = Calendar.current
        let target = currentMaintenanceDate(now: now, calendar: calendar)
        guard now >= target else { return false }
        guard let lastRun else { return true }
        return lastRun < target
    }

    private func currentMaintenanceDate(now: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        var target = DateComponents()
        target.calendar = calendar
        target.timeZone = calendar.timeZone
        target.yearForWeekOfYear = components.yearForWeekOfYear
        target.weekOfYear = components.weekOfYear
        target.weekday = 1
        target.hour = 3
        target.minute = 0
        target.second = 0
        return calendar.date(from: target) ?? now
    }

    private func nextMaintenanceDate(after date: Date = Date()) -> Date {
        let calendar = Calendar.current
        return calendar.nextDate(
            after: date,
            matching: DateComponents(hour: 3, minute: 0, second: 0, weekday: 1),
            matchingPolicy: .nextTime
        ) ?? date.addingTimeInterval(7 * 24 * 60 * 60)
    }

    private func registerBackgroundMaintenance() {
        #if canImport(BackgroundTasks) && os(iOS)
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.maintenanceTaskIdentifier,
            using: nil
        ) { [weak self] task in
            guard let self, let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self.handleBackgroundMaintenance(processingTask)
        }
        #endif
    }

    private func scheduleBackgroundMaintenance() {
        #if canImport(BackgroundTasks) && os(iOS)
        // BGTaskScheduler is unavailable on the iOS Simulator — submit() always
        // fails there with .unavailable. Skip the call so the log isn't poisoned
        // with a misleading ERROR on every simulator launch.
        #if targetEnvironment(simulator)
        log.debug("Skipping BGTaskScheduler.submit on simulator (unsupported).")
        return
        #else
        let request = BGProcessingTaskRequest(identifier: Self.maintenanceTaskIdentifier)
        request.earliestBeginDate = nextMaintenanceDate()
        request.requiresExternalPower = false
        request.requiresNetworkConnectivity = false

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            log.error("Failed to schedule background maintenance: \(error.localizedDescription, privacy: .public)")
        }
        #endif
        #endif
    }

    #if canImport(BackgroundTasks) && os(iOS)
    private func handleBackgroundMaintenance(_ task: BGProcessingTask) {
        scheduleBackgroundMaintenance()

        let container = modelContainer
        let defaults = self.defaults
        let lastRunKey = self.lastRunKey
        let log = self.log
        let operation = Task.detached(priority: .background) {
            Self.performMaintenance(
                container: container,
                defaults: defaults,
                lastRunKey: lastRunKey,
                log: log,
                reason: "background processing"
            )
        }

        task.expirationHandler = {
            operation.cancel()
        }

        Task {
            let success = await operation.value
            task.setTaskCompleted(success: success)
        }
    }
    #endif
}
