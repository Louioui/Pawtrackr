import XCTest
import SwiftData
@testable import Pawtrackr

final class InventoryTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema(PawtrackrSchema.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
    }

    func testInventoryItem_TracksStockChanges() throws {
        let item = InventoryItem(name: "Shampoo", category: "Supplies", unit: "Bottles", costPerUnit: 15.0)
        item.currentStock = 10.0
        context.insert(item)
        
        let tx = InventoryTransaction(item: item, quantityChange: -1.0, note: "Used for session")
        context.insert(tx)
        
        item.currentStock += tx.quantityChange
        try context.save()
        
        XCTAssertEqual(item.currentStock, 9.0)
        XCTAssertEqual(item.transactions?.count, 1)
    }
}
