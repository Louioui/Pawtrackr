import AppIntents
import Foundation
import SwiftData
import OSLog

// MARK: - Check In Pet Intent
struct CheckInPetIntent: AppIntent {
    static var title: LocalizedStringResource = "Check In Pet"
    static var description = IntentDescription("Starts a new grooming session for a specific pet.")

    @Parameter(title: "Pet Name")
    var petName: String

    @MainActor
    func perform() async throws -> some IntentResult {
        let container = try IntentContainerProvider.sharedContainer()
        let context = ModelContext(container)
        
        var descriptor = FetchDescriptor<Pet>(
            predicate: #Predicate { $0.name == petName }
        )
        descriptor.fetchLimit = 1
        
        guard let pet = try context.fetch(descriptor).first else {
            throw AppError.database("Pet '\(petName)' not found.")
        }
        
        if pet.activeVisit != nil {
            return .result()
        }
        
        let visitRepo = VisitRepository(modelContainer: container, eventBus: GlobalEventBus())
        _ = try await visitRepo.checkIn(pet: pet, date: .now)
        
        return .result()
    }
}

// MARK: - Get Business Stats Intent
struct GetBusinessStatsIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Business Stats"
    static var description = IntentDescription("Provides a quick summary of today's performance.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let container = try IntentContainerProvider.sharedContainer()
        let repo = DashboardRepository(modelContainer: container)
        
        let kpis = try await repo.fetchKPIs()
        
        let summary = """
        Today's Summary:
        - \(kpis.appointmentsToday) appointments scheduled.
        - \(kpis.completedToday) visits completed.
        - Total revenue: \(kpis.revenueToday.moneyString).
        - \(kpis.inProgressCount) sessions still in progress.
        """
        
        return .result(value: summary)
    }
}

// MARK: - Container Provider
struct IntentContainerProvider {
    static func sharedContainer() throws -> ModelContainer {
        let schema = Schema(PawtrackrSchema.models)
        let config = ModelConfiguration(
            "Pawtrackr",
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: PawtrackrMigrationPlan.self,
            configurations: [config]
        )
    }
}

// MARK: - Shortcuts
struct PawtrackrShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CheckInPetIntent(),
            phrases: [
                "Check in a pet in \(.applicationName)",
                "Start session for \(\.$petName) in \(.applicationName)",
                "Check in \(\.$petName) with \(.applicationName)"
            ],
            shortTitle: "Check In Pet",
            systemImageName: "play.circle.fill"
        )
        
        AppShortcut(
            intent: GetBusinessStatsIntent(),
            phrases: [
                "How is my business doing today in \(.applicationName)",
                "Get my revenue in \(.applicationName)",
                "Show stats in \(.applicationName)"
            ],
            shortTitle: "Business Stats",
            systemImageName: "chart.bar.fill"
        )
    }
}
