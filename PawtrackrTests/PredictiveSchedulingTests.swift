import XCTest
import SwiftData
@testable import Pawtrackr

final class PredictiveSchedulingTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema(PawtrackrSchema.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
    }

    func testGenerateSuggestions_DogOverdueAfterOneMonth() async throws {
        let owner = Client(firstName: "Alice", lastName: "Smith")
        context.insert(owner)
        let pet = Pet(name: "Charlie", species: .dog)
        pet.owner = owner
        context.insert(pet)

        let cal = Calendar.current
        // A single completed visit 20 days ago — under the ~30-day dog cadence.
        let d1 = cal.date(byAdding: .day, value: -20, to: Date())!
        let visit = Visit(pet: pet, startedAt: d1)
        visit.endedAt = d1.addingTimeInterval(3600)
        context.insert(visit)
        try context.save()

        let actor = PredictiveSchedulingActor(modelContainer: container)
        let none = try await actor.generateSuggestions()
        XCTAssertEqual(none.count, 0, "A dog under the 1-month cadence should not be flagged.")

        // Move the last visit to 40 days ago — past the dog cadence.
        let d2 = cal.date(byAdding: .day, value: -40, to: Date())!
        visit.startedAt = d2
        visit.endedAt = d2.addingTimeInterval(3600)
        try context.save()

        let flagged = try await actor.generateSuggestions()
        XCTAssertEqual(flagged.count, 1, "A dog past the 1-month cadence should be flagged.")
        XCTAssertEqual(flagged.first?.petName, "Charlie")
    }

    func testGenerateSuggestions_CatWaitsSixMonths() async throws {
        let owner = Client(firstName: "Bob", lastName: "Jones")
        context.insert(owner)
        let pet = Pet(name: "Whiskers", species: .cat)
        pet.owner = owner
        context.insert(pet)

        let cal = Calendar.current
        // 60 days since last visit — a dog would be overdue, but a cat should NOT.
        let d1 = cal.date(byAdding: .day, value: -60, to: Date())!
        let visit = Visit(pet: pet, startedAt: d1)
        visit.endedAt = d1.addingTimeInterval(3600)
        context.insert(visit)
        try context.save()

        let actor = PredictiveSchedulingActor(modelContainer: container)
        let none = try await actor.generateSuggestions()
        XCTAssertEqual(none.count, 0, "A cat under the 6-month cadence should not be flagged.")

        // 200 days since last visit — past the 6-month cat cadence.
        let d2 = cal.date(byAdding: .day, value: -200, to: Date())!
        visit.startedAt = d2
        visit.endedAt = d2.addingTimeInterval(3600)
        try context.save()

        let flagged = try await actor.generateSuggestions()
        XCTAssertEqual(flagged.count, 1, "A cat past the 6-month cadence should be flagged.")
        XCTAssertEqual(flagged.first?.petName, "Whiskers")
    }
}
