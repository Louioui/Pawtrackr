import XCTest
import SwiftData
@testable import Pawtrackr

final class PetBITests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema([Pet.self, Visit.self, VisitItem.self, Client.self, Payment.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
    }

    func testLifetimeValue_CalculatesCorrectSum() {
        let pet = Pet(name: "Max", species: .dog)
        context.insert(pet)
        
        let visit1 = Visit(pet: pet, startedAt: .now.addingTimeInterval(-86400))
        visit1.total = 50.0
        visit1.endedAt = .now.addingTimeInterval(-86400 + 3600)
        
        let visit2 = Visit(pet: pet, startedAt: .now)
        visit2.total = 75.0
        visit2.endedAt = .now.addingTimeInterval(3600)
        
        XCTAssertEqual(pet.lifetimeValue, 125.0)
        XCTAssertEqual(pet.completedVisitCount, 2)
    }

    func testEngagementScore_WithNoHistory_ReturnsDefault() {
        let pet = Pet(name: "Max", species: .dog)
        XCTAssertEqual(pet.engagementScore, 0.5)
    }

    func testEngagementScore_OnSchedule_ReturnsPerfectScore() {
        let pet = Pet(name: "Max", species: .dog)
        pet.preferredGroomingFrequency = .monthly // ~30 days
        
        // Two visits exactly 30 days apart
        let date1 = Date().addingTimeInterval(-60 * 24 * 3600)
        let date2 = Date().addingTimeInterval(-30 * 24 * 3600)
        
        let v1 = Visit(pet: pet, startedAt: date1)
        v1.endedAt = date1.addingTimeInterval(3600)
        
        let v2 = Visit(pet: pet, startedAt: date2)
        v2.endedAt = date2.addingTimeInterval(3600)
        
        XCTAssertTrue(pet.engagementScore >= 0.99)
    }
}
