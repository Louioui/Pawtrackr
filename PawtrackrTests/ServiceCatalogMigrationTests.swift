import XCTest
import SwiftData
@testable import Pawtrackr

/// `ensureServiceCatalog` runs on every launch on every device. It used to
/// clear every catalog price and re-enable every catalog service each time,
/// and every assignment uploads the row to iCloud. Each "launch" here uses a
/// fresh ModelContext on the same store, as RootView's startup maintenance does.
final class ServiceCatalogMigrationTests: XCTestCase {
    private var container: ModelContainer!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let schema = Schema(PawtrackrSchema.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [config])
    }

    override func tearDownWithError() throws {
        container = nil
        try super.tearDownWithError()
    }

    func testUserPriceAndDisabledServiceSurviveTwoLaunches() throws {
        runLaunch()

        // The salon prices Bath and turns Hair Dye off in Settings → Services.
        let setup = ModelContext(container)
        try service(named: "Bath", in: setup).setBasePrice(Decimal(string: "42.50")!)
        try service(named: "Hair Dye", in: setup).setEnabled(false)
        try setup.save()
        let afterEdit = try snapshot()

        XCTAssertEqual(runLaunch(), 0, "Launch 2 must not save anything.")
        XCTAssertEqual(runLaunch(), 0, "Launch 3 must not save anything.")

        let check = ModelContext(container)
        XCTAssertEqual(try service(named: "Bath", in: check).basePrice, Decimal(string: "42.50"))
        XCTAssertFalse(try service(named: "Hair Dye", in: check).isEnabled)
        XCTAssertEqual(try snapshot(), afterEdit, "No row was rewritten: prices, switches and change stamps are identical.")
    }

    func testUnchangedCatalogSavesNothing() throws {
        XCTAssertEqual(runLaunch(), 1, "The first launch inserts the catalog.")
        let afterFirst = try snapshot()

        XCTAssertEqual(runLaunch(), 0)
        XCTAssertEqual(try snapshot(), afterFirst)
    }

    func testCatalogStillFixesADriftedIconWithoutTouchingPrice() throws {
        runLaunch()
        let edit = ModelContext(container)
        let bath = try service(named: "Bath", in: edit)
        bath.setSystemIcon("questionmark")
        bath.setBasePrice(30)
        try edit.save()

        XCTAssertEqual(runLaunch(), 1, "A real difference is written once.")
        XCTAssertEqual(runLaunch(), 0, "…and then left alone.")

        let check = ModelContext(container)
        let fixed = try service(named: "Bath", in: check)
        XCTAssertEqual(fixed.systemIcon, "shower.fill")
        XCTAssertEqual(fixed.categoryRaw, Service.Category.groom.rawValue)
        XCTAssertEqual(fixed.basePrice, 30)
    }

    func testRetiredBasicGroomIsSwitchedOffOnceAndThenLeftAlone() throws {
        let setup = ModelContext(container)
        setup.insert(Service(name: "Basic Groom", category: .groom, systemIcon: "scissors", basePrice: 50, isEnabled: true))
        try setup.save()

        runLaunch()
        XCTAssertEqual(runLaunch(), 0)

        let check = ModelContext(container)
        let retired = try service(named: "Basic Groom", in: check)
        XCTAssertFalse(retired.isEnabled)
        XCTAssertNil(retired.basePrice)
    }

    // MARK: - Helpers

    /// Runs the migration on a fresh context and returns how many times that
    /// context saved.
    @discardableResult
    private func runLaunch() -> Int {
        let context = ModelContext(container)
        var saves = 0
        let token = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: context, queue: nil) { _ in
            saves += 1
        }
        DataMigrations.ensureServiceCatalog(in: context)
        NotificationCenter.default.removeObserver(token)
        return saves
    }

    private struct Row: Equatable {
        let name: String
        let categoryRaw: String?
        let systemIcon: String?
        let price: Decimal?
        let isEnabled: Bool
        let isPackage: Bool
        let updatedAt: Date
        let lastModifiedBy: UUID
    }

    private func snapshot() throws -> [UUID: Row] {
        let context = ModelContext(container)
        return Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<Service>()).map {
            ($0.uuid, Row(
                name: $0.name, categoryRaw: $0.categoryRaw, systemIcon: $0.systemIcon, price: $0.basePrice,
                isEnabled: $0.isEnabled, isPackage: $0.isPackage, updatedAt: $0.updatedAt, lastModifiedBy: $0.lastModifiedBy
            ))
        })
    }

    private func service(named name: String, in context: ModelContext) throws -> Service {
        try XCTUnwrap(try context.fetch(FetchDescriptor<Service>()).first { $0.name == name }, "No service named \(name)")
    }
}
