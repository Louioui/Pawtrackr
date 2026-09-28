import XCTest
import SwiftData
@testable import Pawtrackr

/// A summary rebuild that finds nothing new must not save.
///
/// The summary rows are mirrored, so a no-op save still uploads them. Before
/// 1.0.3 a rebuild's own save fired NSPersistentStoreRemoteChange, which
/// scheduled the next rebuild, every ~2.4 s for as long as the app was open;
/// an export stayed queued the whole time and the banner never left
/// "upload pending".
@MainActor
final class SummaryRebuildIdempotencyTests: XCTestCase {
    private var storeDirectory: URL!

    override func setUpWithError() throws {
        storeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SummaryRebuild-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: storeDirectory)
        UserDefaults.standard.removeObject(forKey: "lastSummaryRebuildDate")
    }

    func testASecondRebuildOfUnchangedDataDoesNotSave() throws {
        do {
            let context = ModelContext(try makeContainer())
            try seedCompletedVisits(in: context)
            XCTAssertTrue(SummaryUpdater.rebuildAllSummaries(in: context), "The first rebuild creates the rows.")
        }

        // Reopened, so every amount and date is read back from SQLite the
        // way an import-triggered rebuild reads it.
        let container = try makeContainer()
        XCTAssertFalse(SummaryUpdater.rebuildAllSummaries(in: ModelContext(container)))
        XCTAssertFalse(SummaryUpdater.rebuildAllSummaries(in: ModelContext(container)))
    }

    func testARebuildStillSavesWhenAVisitIsAdded() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        try seedCompletedVisits(in: context)
        SummaryUpdater.rebuildAllSummaries(in: context)

        let pet = try XCTUnwrap(try context.fetch(FetchDescriptor<Pet>()).first)
        let today = Date.now.addingTimeInterval(-7_200)
        let visit = Visit(pet: pet, startedAt: today)
        context.insert(visit)
        visit.markCheckedOut(total: Decimal(string: "41.10")!, now: today.addingTimeInterval(3_600))
        try context.save()

        XCTAssertTrue(SummaryUpdater.rebuildAllSummaries(in: ModelContext(container)))
        let day = Calendar.current.startOfDay(for: today.addingTimeInterval(3_600))
        let rows = try ModelContext(container).fetch(FetchDescriptor<DaySummary>())
        XCTAssertEqual(rows.first { $0.day == day }?.revenue, Decimal(string: "41.10")!)
        let insight = try XCTUnwrap(try ModelContext(container).fetch(FetchDescriptor<ClientInsightSummary>()).first)
        XCTAssertEqual(insight.visitCount, 4)
    }

    /// Two devices each inserted a row for the same day before importing the
    /// other's. Deleting either one lets the devices delete each other's.
    func testDuplicateRowsAreUpdatedNotDeleted() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        try seedCompletedVisits(in: context)
        SummaryUpdater.rebuildAllSummaries(in: context)
        let day = try XCTUnwrap(try context.fetch(FetchDescriptor<DaySummary>()).first?.day)
        context.insert(DaySummary(day: day, revenue: 1, visitCount: 9))
        try context.save()

        XCTAssertTrue(SummaryUpdater.rebuildAllSummaries(in: ModelContext(container)), "The stale copy is corrected.")
        let copies = try ModelContext(container).fetch(FetchDescriptor<DaySummary>()).filter { $0.day == day }
        XCTAssertEqual(copies.count, 2)
        XCTAssertEqual(Set(copies.map(\.visitCount)).count, 1)
        XCTAssertEqual(Set(copies.map { $0.revenue.roundedMoney() }).count, 1)
        XCTAssertFalse(SummaryUpdater.rebuildAllSummaries(in: ModelContext(container)))
    }

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(PawtrackrSchema.models)
        let config = ModelConfiguration(
            schema: schema,
            url: storeDirectory.appendingPathComponent("Pawtrackr.store"),
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Amounts that don't survive a binary round trip exactly, on two days,
    /// each with a line item so service summaries are written too.
    private func seedCompletedVisits(in context: ModelContext) throws {
        let client = Client(firstName: "Ava", lastName: "Martinez")
        let pet = Pet(name: "Milo", species: .dog)
        context.insert(client)
        context.insert(pet)
        client.addPet(pet)

        for (daysAgo, price) in [(3.0, "33.33"), (3.0, "19.99"), (10.0, "12.34")] {
            let amount = try XCTUnwrap(Decimal(string: price))
            let start = Date.now.addingTimeInterval(-daysAgo * 86_400)
            let visit = Visit(pet: pet, startedAt: start)
            context.insert(visit)
            let item = VisitItem(name: "Bath", unitPrice: amount, visit: visit)
            context.insert(item)
            visit.addItem(item)
            visit.markCheckedOut(total: amount, now: start.addingTimeInterval(3_600))
        }
        try context.save()
    }
}
