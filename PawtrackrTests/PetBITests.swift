import XCTest
import SwiftData
@testable import Pawtrackr

final class PetBITests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema(PawtrackrSchema.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
    }

    func testLifetimeValue_CalculatesCorrectSum() {
        let pet = Pet(name: "Max", species: .dog)
        context.insert(pet)
        
        let visit1 = Visit(pet: pet, startedAt: .now.addingTimeInterval(-86400))
        visit1.total = Decimal(50)
        visit1.endedAt = .now.addingTimeInterval(-86400 + 3600)
        
        let visit2 = Visit(pet: pet, startedAt: .now)
        visit2.total = Decimal(75)
        visit2.endedAt = .now.addingTimeInterval(3600)
        
        XCTAssertEqual(pet.lifetimeValue, Decimal(125))
        XCTAssertEqual(pet.completedVisitCount, 2)
    }

    func testIsAggressive_DetectsEnglishAndSpanishTags() {
        let pet = Pet(name: "Rex", species: .dog)
        XCTAssertFalse(pet.isAggressive)

        pet.setBehaviorTags(["Calm"])
        XCTAssertFalse(pet.isAggressive)

        pet.setBehaviorTags(["Aggressive"])
        XCTAssertTrue(pet.isAggressive)

        // Tags are stored as their localized display string, so a Spanish device
        // stores "Agresivo" — the red safety banner must still trigger (the
        // iPhone/iPad bug).
        pet.setBehaviorTags(["Agresivo"])
        XCTAssertTrue(pet.isAggressive, "Spanish 'Agresivo' tag must be detected as aggressive.")

        XCTAssertTrue(Pet.isAggressiveTag("Muerde"))
        XCTAssertTrue(Pet.isAggressiveTag("Peligroso"))
        XCTAssertFalse(Pet.isAggressiveTag("Necesidades Especiales"))
        XCTAssertFalse(Pet.isAggressiveTag("Tranquilo"))
    }

    func testSuggestedCadence_DogMonthly_CatSixMonths() throws {
        let cal = Calendar.current
        func makePet(_ species: Species, lastVisitDaysAgo days: Int) throws -> Pet {
            let p = Pet(name: "P", species: species)
            context.insert(p)
            let d = cal.date(byAdding: .day, value: -days, to: .now)!
            let v = Visit(pet: p, startedAt: d)
            v.endedAt = d.addingTimeInterval(3600)
            context.insert(v)
            try context.save()
            return p
        }
        // Dog cadence ~1 month.
        XCTAssertFalse(try makePet(.dog, lastVisitDaysAgo: 20).isOverdue)
        XCTAssertTrue(try makePet(.dog, lastVisitDaysAgo: 40).isOverdue)
        // Cat cadence ~6 months — a 60-day-old visit must NOT be overdue.
        XCTAssertFalse(try makePet(.cat, lastVisitDaysAgo: 60).isOverdue)
        XCTAssertTrue(try makePet(.cat, lastVisitDaysAgo: 200).isOverdue)
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
