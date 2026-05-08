import AppIntents
import Foundation
import SwiftData

struct CheckInPetIntent: AppIntent {
    static var title: LocalizedStringResource = "Check In Pet"
    static var description = IntentDescription("Starts a new session for a specific pet.")

    @Parameter(title: "Pet Name")
    var petName: String

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let query = petName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return .result(value: "Enter a pet name to check in.")
        }

        let schema = Schema(PawtrackrSchema.models)
        let config = ModelConfiguration(
            "Pawtrackr",
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: PawtrackrMigrationPlan.self,
            configurations: [config]
        )
        let context = container.mainContext
        let descriptor = FetchDescriptor<Pet>(sortBy: [SortDescriptor(\.name)])
        let pets = try context.fetch(descriptor)
        let match = pets.first { $0.name.compare(query, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
            ?? pets.first { $0.name.localizedStandardContains(query) }

        guard let pet = match else {
            return .result(value: "No pet found matching \(query).")
        }

        guard pet.activeVisit == nil else {
            return .result(value: "\(pet.name) is already checked in.")
        }

        let repository = VisitRepository(modelContainer: container, eventBus: GlobalEventBus())
        _ = try await repository.checkIn(pet: pet, date: Date())

        return .result(value: "Checked in \(pet.name).")
    }
}

struct PawtrackrShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CheckInPetIntent(),
            phrases: [
                "Check in a pet in \(.applicationName)",
                "Start a session in \(.applicationName)"
            ],
            shortTitle: "Check In Pet",
            systemImageName: "play.fill"
        )
    }
}
