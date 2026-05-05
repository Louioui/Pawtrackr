import XCTest
import SwiftData
@testable import Pawtrackr

@MainActor
final class DashboardRepositoryTests: XCTestCase {
    var container: ModelContainer!
    var repository: DashboardRepository!
    var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema(PawtrackrSchema.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        context = container.mainContext
        repository = DashboardRepository(modelContainer: container)
    }

    func testFetchKPIs_ReturnsCorrectAggregation() async throws {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        
        // Setup some data
        let pet = Pet(name: "Buddy", species: .dog)
        context.insert(pet)
        
        let appt = Appointment(pet: pet, date: today.addingTimeInterval(3600))
        context.insert(appt)
        
        let visit = Visit(pet: pet, startedAt: .now)
        context.insert(visit)
        
        let summary = DaySummary(day: today, revenue: 100.0, visitCount: 5)
        context.insert(summary)
        
        try context.save()
        
        let kpis = try await repository.fetchKPIs()
        
        XCTAssertEqual(kpis.appointmentsToday, 1)
        XCTAssertEqual(kpis.inProgressCount, 1)
        XCTAssertEqual(kpis.revenueToday, 100.0)
        XCTAssertEqual(kpis.completedToday, 5)
    }

    func testFetchOverduePets_UsesModelLogic() async throws {
        let pet = Pet(name: "OldTimer", species: .dog)
        pet.preferredGroomingFrequency = .weekly
        // Last visit was 2 weeks ago
        let twoWeeksAgo = Calendar.current.date(byAdding: .day, value: -14, to: .now)!
        let visit = Visit(pet: pet, startedAt: twoWeeksAgo)
        visit.endedAt = twoWeeksAgo.addingTimeInterval(3600)
        
        context.insert(pet)
        context.insert(visit)
        pet.updatedAt = twoWeeksAgo // Manually set to simulate aging
        
        try context.save()
        
        let overdue = try await repository.fetchOverduePets(limit: 10)
        XCTAssertEqual(overdue.count, 1)
        XCTAssertEqual(overdue.first?.name, "OldTimer")
    }
}
