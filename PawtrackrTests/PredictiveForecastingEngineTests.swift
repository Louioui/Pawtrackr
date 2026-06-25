import XCTest
import SwiftData
@testable import Pawtrackr

@MainActor
final class PredictiveForecastingEngineTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema(PawtrackrSchema.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
    }

    override func tearDownWithError() throws {
        container = nil
        context = nil
    }

    func testAnalyzeGroomingTrends_EmptyStoreReturnsFiniteZeroForecast() async throws {
        let engine = PredictiveForecastingEngine(modelContainer: container)

        let forecast = await engine.analyzeGroomingTrends(over: 7)

        XCTAssertEqual(forecast.count, 7)
        XCTAssertEqual(Set(forecast.values), [Decimal.zero])
        XCTAssertEqual(Set(forecast.keys), expectedFutureDays(count: 7))
    }

    func testAnalyzeGroomingTrends_LowDensityUsesSimpleDailyAverage() async throws {
        let owner = Client(firstName: "Maya", lastName: "Lee")
        context.insert(owner)
        let pet = Pet(name: "Luna", species: .dog)
        pet.owner = owner
        context.insert(pet)

        let calendar = Calendar.current
        for (offset, total) in [(-3, Decimal(90)), (-2, Decimal(30)), (-1, Decimal(60))] {
            let day = calendar.date(byAdding: .day, value: offset, to: Date())!
            let visit = Visit(pet: pet, startedAt: day.addingTimeInterval(-3600))
            visit.markCheckedOut(total: total, now: day)
            context.insert(visit)
        }
        try context.save()

        let engine = PredictiveForecastingEngine(modelContainer: container)

        let forecast = await engine.analyzeGroomingTrends(over: 5)

        XCTAssertEqual(forecast.count, 5)
        XCTAssertEqual(Set(forecast.values), [Decimal(60)])
        XCTAssertEqual(Set(forecast.keys), expectedFutureDays(count: 5))
    }

    private func expectedFutureDays(count: Int) -> Set<Date> {
        let calendar = Calendar.current
        return Set((1...count).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: Date()))
        })
    }
}
