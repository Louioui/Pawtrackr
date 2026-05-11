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

    func testGenerateSuggestions_IdentifiesOverduePet() async throws {
        let owner = Client(firstName: "Alice", lastName: "Smith")
        context.insert(owner)
        let pet = Pet(name: "Charlie", species: .dog)
        pet.owner = owner
        context.insert(pet)
        
        // Create a history of visits every 4 weeks (28 days)
        let cal = Calendar.current
        let date1 = cal.date(byAdding: .day, value: -60, to: Date())!
        let date2 = cal.date(byAdding: .day, value: -32, to: Date())! // 28 days interval
        
        let v1 = Visit(pet: pet, startedAt: date1)
        v1.endedAt = date1.addingTimeInterval(3600)
        
        let v2 = Visit(pet: pet, startedAt: date2)
        v2.endedAt = date2.addingTimeInterval(3600)
        
        try context.save()
        
        let actor = PredictiveSchedulingActor(modelContainer: container)
        let suggestions = try await actor.generateSuggestions()
        
        // It has been 32 days since last visit. 
        // Interval is 28 days. 1.2 * 28 = 33.6 days.
        // If it's been 32 days, it's NOT yet 20% past.
        XCTAssertEqual(suggestions.count, 0)
        
        // Now make it 40 days since last visit
        let date3 = cal.date(byAdding: .day, value: -40, to: Date())!
        v2.startedAt = date3
        v2.endedAt = date3.addingTimeInterval(3600)
        try context.save()
        
        let newSuggestions = try await actor.generateSuggestions()
        XCTAssertEqual(newSuggestions.count, 1)
        XCTAssertEqual(newSuggestions.first?.petName, "Charlie")
    }
}
