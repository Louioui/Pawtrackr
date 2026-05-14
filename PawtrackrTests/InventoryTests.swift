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
        let item = InventoryItem(name: "Shampoo", category: "Supplies", unit: "Bottles", costPerUnit: Decimal(15))
        item.currentStock = Decimal(10)
        context.insert(item)
        
        let tx = InventoryTransaction(item: item, quantityChange: Decimal(-1), note: "Used for session")
        context.insert(tx)
        
        item.currentStock += tx.quantityChange
        try context.save()
        
        XCTAssertEqual(item.currentStock, Decimal(9))
        XCTAssertEqual(item.transactions?.count, 1)
    }
}
