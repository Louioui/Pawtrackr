import XCTest
import SwiftData
@testable import Pawtrackr

/// Aggregation-depth tests for the summary models powering the Insights screen.
/// Complements InsightsViewModelTests, which covers the VM-level wiring;
/// this file targets the raw SummaryUpdater output and edge cases like
/// multi-day, same-day collisions, and delete-then-rebuild.
@MainActor
final class InsightsAggregationTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var client: Client!
    var pet: Pet!
    var bath: Service!
    var nailTrim: Service!

    override func setUpWithError() throws {
        let schema = Schema(PawtrackrSchema.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [config])
        context = container.mainContext

        client = Client(firstName: "Jane", lastName: "Doe", phone: "5551234567")
        context.insert(client)
        pet = Pet(name: "Buddy", species: .dog)
        pet.owner = client
        context.insert(pet)

        bath = Service(name: "Bath", category: .groom, basePrice: Decimal(30))
        nailTrim = Service(name: "Nail Trim", category: .addOn, basePrice: Decimal(15))
        context.insert(bath)
        context.insert(nailTrim)
        try context.save()
    }

    override func tearDownWithError() throws {
        container = nil; context = nil; client = nil; pet = nil; bath = nil; nailTrim = nil
    }

    func testTwoVisitsSameDay_SumIntoOneAggregateRow() throws {
        let now = Date()
        seedCheckedOutVisit(at: now, items: [(bath, 30)], paymentAmount: 30)
        seedCheckedOutVisit(at: now, items: [(nailTrim, 15)], paymentAmount: 15)

        SummaryUpdater.rebuildDay(for: now, in: context)

        let day = Calendar.current.startOfDay(for: now)
        let summaries = try context.fetch(FetchDescriptor<DaySummary>(predicate: #Predicate<DaySummary> { $0.day == day }))
        let aggregate = SummaryUpdater.collapsedDayAggregates(from: summaries)[day]
        XCTAssertEqual(aggregate?.revenue, Decimal(string: "45.00"))
        XCTAssertEqual(aggregate?.visitCount, 2)
    }

    func testTwoVisitsDifferentDays_TrackedSeparately() throws {
        let cal = Calendar.current
        let today = Date()
        let yesterday = try XCTUnwrap(cal.date(byAdding: .day, value: -1, to: today))

        seedCheckedOutVisit(at: today, items: [(bath, 30)], paymentAmount: 30)
        seedCheckedOutVisit(at: yesterday, items: [(bath, 20)], paymentAmount: 20)

        SummaryUpdater.rebuildDay(for: today, in: context)
        SummaryUpdater.rebuildDay(for: yesterday, in: context)

        let summaries = try context.fetch(FetchDescriptor<DaySummary>())
        let aggregates = SummaryUpdater.collapsedDayAggregates(from: summaries)
        XCTAssertEqual(aggregates[cal.startOfDay(for: today)]?.revenue, Decimal(string: "30.00"))
        XCTAssertEqual(aggregates[cal.startOfDay(for: yesterday)]?.revenue, Decimal(string: "20.00"))
    }

    func testVisitDeletion_FollowedByRebuild_ZeroesDaySummary() throws {
        let now = Date()
        let visit = seedCheckedOutVisit(at: now, items: [(bath, 30)], paymentAmount: 30)
        SummaryUpdater.rebuildDay(for: now, in: context)

        context.delete(visit)
        try context.save()
        SummaryUpdater.rebuildDay(for: now, in: context)

        let day = Calendar.current.startOfDay(for: now)
        let summaries = try context.fetch(FetchDescriptor<DaySummary>(predicate: #Predicate<DaySummary> { $0.day == day }))
        let aggregate = SummaryUpdater.collapsedDayAggregates(from: summaries)[day]
        XCTAssertEqual(aggregate?.revenue ?? .zero, .zero)
        XCTAssertEqual(aggregate?.visitCount ?? 0, 0)
    }

    func testCategoryDaySummary_TracksMixedCategoriesFromOneVisit() throws {
        let now = Date()
        seedCheckedOutVisit(at: now, items: [(bath, 30), (nailTrim, 15)], paymentAmount: 45)

        SummaryUpdater.rebuildDay(for: now, in: context)

        let day = Calendar.current.startOfDay(for: now)
        let cats = try context.fetch(FetchDescriptor<CategoryDaySummary>(predicate: #Predicate<CategoryDaySummary> { $0.day == day }))
        let counts = SummaryUpdater.collapsedCategoryCounts(from: cats)
        XCTAssertEqual(counts["Grooming"], 1)
        XCTAssertEqual(counts["Add-on"], 1)
    }

    func testServiceDaySummary_CountsServiceFrequencyAcrossVisits() throws {
        let now = Date()
        seedCheckedOutVisit(at: now, items: [(bath, 30)], paymentAmount: 30)
        seedCheckedOutVisit(at: now, items: [(bath, 30)], paymentAmount: 30)
        seedCheckedOutVisit(at: now, items: [(nailTrim, 15)], paymentAmount: 15)

        SummaryUpdater.rebuildDay(for: now, in: context)

        let day = Calendar.current.startOfDay(for: now)
        let summaries = try context.fetch(FetchDescriptor<ServiceDaySummary>(predicate: #Predicate<ServiceDaySummary> { $0.day == day }))
        let counts = SummaryUpdater.collapsedServiceCounts(from: summaries)
        XCTAssertEqual(counts["Bath"], 2)
        XCTAssertEqual(counts["Nail Trim"], 1)
    }

    func testRebuildDay_SecondPass_DoesNotDoubleCount() throws {
        let now = Date()
        seedCheckedOutVisit(at: now, items: [(bath, 30)], paymentAmount: 30)

        SummaryUpdater.rebuildDay(for: now, in: context)
        SummaryUpdater.rebuildDay(for: now, in: context)
        SummaryUpdater.rebuildDay(for: now, in: context)

        let day = Calendar.current.startOfDay(for: now)
        let summaries = try context.fetch(FetchDescriptor<DaySummary>(predicate: #Predicate<DaySummary> { $0.day == day }))
        let aggregate = SummaryUpdater.collapsedDayAggregates(from: summaries)[day]
        XCTAssertEqual(aggregate?.revenue, Decimal(string: "30.00"), "Rebuilds should be idempotent — revenue must not balloon on repeat calls.")
        XCTAssertEqual(aggregate?.visitCount, 1)
    }

    // MARK: - Helpers

    @discardableResult
    private func seedCheckedOutVisit(
        at date: Date,
        items: [(Service, Decimal)],
        paymentAmount: Decimal
    ) -> Visit {
        let visit = Visit(pet: pet, startedAt: date.addingTimeInterval(-1800))
        context.insert(visit)
        for (service, price) in items {
            visit.addItem(title: service.name, unitPrice: price, service: service)
        }
        let payment = Payment(amount: paymentAmount, method: .cash, paidAt: date)
        context.insert(payment)
        visit.attachPayment(payment)
        visit.markCheckedOut(total: paymentAmount, now: date)
        try? context.save()
        return visit
    }
}
