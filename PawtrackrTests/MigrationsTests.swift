import XCTest
import SwiftData
@testable import Pawtrackr

final class MigrationsTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema(PawtrackrSchema.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
    }

    func testEnsureServiceCatalog_CreatesDefaults() throws {
        // Initial state: potentially empty or seeded by container init
        // We'll clear and run the migration
        let existing = try context.fetch(FetchDescriptor<Service>())
        for s in existing { context.delete(s) }
        try context.save()
        
        DataMigrations.ensureServiceCatalog(in: context)
        
        let services = try context.fetch(FetchDescriptor<Service>())
        XCTAssertGreaterThan(services.count, 5)
        XCTAssertTrue(services.contains(where: { $0.name == "Full Package" }))
    }
    
    func testCoercePets_StandardizesGenders() throws {
        let pet = Pet(name: "Test", species: .dog)
        // Manually set a 'bad' state if possible (though enum prevents it, 
        // older data might have been different)
        context.insert(pet)
        try context.save()
        
        DataMigrations.coercePets(in: context)
        
        // Refresh and verify
        let fetched = try context.fetch(FetchDescriptor<Pet>()).first!
        XCTAssertTrue(fetched.gender == .male || fetched.gender == .female)
    }
}
