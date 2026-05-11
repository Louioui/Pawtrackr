import XCTest
import SwiftData
@testable import Pawtrackr

final class ImportServiceTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema(PawtrackrSchema.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
    }

    @MainActor
    func testImportFromCSV_MapsFieldsCorrectly() throws {
        let csvData = """
        First Name,Last Name,Phone Number,Pet Name,Breed
        Alice,Smith,5551234,Charlie,Beagle
        Bob,Jones,5556789,Rex,Boxer
        """
        
        let result = try ImportService.shared.importFromCSV(data: csvData, context: context)
        
        XCTAssertEqual(result.clientsCreated, 2)
        XCTAssertEqual(result.petsCreated, 2)
        
        let clients = try context.fetch(FetchDescriptor<Client>())
        XCTAssertTrue(clients.contains(where: { $0.firstName == "Alice" }))
        XCTAssertTrue(clients.contains(where: { $0.phone == "5551234" }))
        
        let pets = try context.fetch(FetchDescriptor<Pet>())
        XCTAssertTrue(pets.contains(where: { $0.name == "Charlie" }))
        XCTAssertTrue(pets.contains(where: { $0.breed == "Beagle" }))
    }
}
