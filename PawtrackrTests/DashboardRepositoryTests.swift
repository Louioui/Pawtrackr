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
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
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
        
        let appt = Appointment(date: today.addingTimeInterval(3600), pet: pet, user: nil)
        context.insert(appt)
        
        let visit = Visit(pet: pet, startedAt: .now)
        context.insert(visit)
        
        let summary = DaySummary(day: today, revenue: Decimal(100), visitCount: 5)
        context.insert(summary)
        
        try context.save()
        
        let kpis = try await repository.fetchKPIs()
        
        XCTAssertEqual(kpis.appointmentsToday, 1)
        XCTAssertEqual(kpis.inProgressCount, 1)
        XCTAssertEqual(kpis.revenueToday, Decimal(100))
        XCTAssertEqual(kpis.completedToday, 5)
    }

    func testSummaryFetches_CollapseDuplicateCloudKitCacheRows() async throws {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)

        context.insert(DaySummary(day: today, revenue: Decimal(100), visitCount: 5))
        context.insert(DaySummary(day: today, revenue: Decimal(80), visitCount: 4))
        context.insert(ServiceDaySummary(day: today, serviceName: "Bath", count: 3))
        context.insert(ServiceDaySummary(day: today, serviceName: "Bath", count: 2))
        context.insert(CategoryDaySummary(day: today, categoryRaw: "Grooming", count: 3))
        context.insert(CategoryDaySummary(day: today, categoryRaw: "Grooming", count: 2))
        try context.save()

        let kpis = try await repository.fetchKPIs()
        XCTAssertEqual(kpis.revenueToday, Decimal(100))
        XCTAssertEqual(kpis.completedToday, 5)

        let services = try await repository.fetchServiceDistribution(days: 1)
        XCTAssertEqual(services["Bath"], 3)

        let categories = try await repository.fetchCategoryDistribution(days: 1)
        XCTAssertEqual(categories["Grooming"], 3)

        let revenue = try await repository.fetchRevenueSeries(days: 1)
        XCTAssertEqual(revenue[today], Decimal(100))
    }

    func testDedupeSummaryCaches_DeletesDuplicateRows() throws {
        let today = Calendar.current.startOfDay(for: .now)

        context.insert(DaySummary(day: today, revenue: Decimal(100), visitCount: 5))
        context.insert(DaySummary(day: today, revenue: Decimal(80), visitCount: 4))
        context.insert(ServiceDaySummary(day: today, serviceName: "Bath", count: 3))
        context.insert(ServiceDaySummary(day: today, serviceName: "Bath", count: 2))
        context.insert(CategoryDaySummary(day: today, categoryRaw: "Grooming", count: 3))
        context.insert(CategoryDaySummary(day: today, categoryRaw: "Grooming", count: 2))
        try context.save()

        SummaryUpdater.dedupeSummaryCaches(in: context)

        XCTAssertEqual(try context.fetch(FetchDescriptor<DaySummary>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ServiceDaySummary>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CategoryDaySummary>()).count, 1)
    }

    func testFetchOverduePets_UsesModelLogic() async throws {
        let pet = Pet(name: "OldTimer", species: .dog)
        pet.preferredGroomingFrequency = .weekly
        // Last visit was 2 weeks ago
        let twoWeeksAgo = Calendar.current.date(byAdding: .day, value: -14, to: .now)!
        let visit = Visit(pet: pet, startedAt: twoWeeksAgo)
        visit.markCheckedOut(now: twoWeeksAgo.addingTimeInterval(3600))
        
        context.insert(pet)
        context.insert(visit)
        pet.updatedAt = twoWeeksAgo // Manually set to simulate aging
        
        try context.save()
        
        let overdue = try await repository.fetchOverduePets(limit: 10)
        let overduePets = overdue.compactMap { context.model(for: $0) as? Pet }
        XCTAssertEqual(overdue.count, 1)
        XCTAssertEqual(overduePets.first?.name, "OldTimer")
    }
}
