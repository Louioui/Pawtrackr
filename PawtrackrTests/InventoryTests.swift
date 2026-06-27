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
        try context.save()
        
        XCTAssertEqual(item.currentStock, Decimal(9))
        XCTAssertEqual(item.transactions?.count, 1)
    }

    func testInventoryTransaction_AppliesQuantityChangeToItemStock() throws {
        let item = InventoryItem(name: "Conditioner", category: "Supplies", unit: "Bottles", costPerUnit: Decimal(12))
        item.currentStock = Decimal(10)
        context.insert(item)

        let tx = InventoryTransaction(item: item, quantityChange: Decimal(-2), note: "Used during checkout")
        context.insert(tx)
        try context.save()

        // Re-fetch from a FRESH context so the assertions verify persisted
        // store state rather than cached in-memory objects from `context`.
        let verifyContext = ModelContext(container)
        let itemUUID = item.uuid
        let savedItem = try XCTUnwrap(
            try verifyContext.fetch(FetchDescriptor<InventoryItem>(
                predicate: #Predicate { $0.uuid == itemUUID }
            )).first
        )
        XCTAssertEqual(savedItem.currentStock, Decimal(8))

        let txUUID = tx.uuid
        let savedTx = try XCTUnwrap(
            try verifyContext.fetch(FetchDescriptor<InventoryTransaction>(
                predicate: #Predicate { $0.uuid == txUUID }
            )).first
        )
        XCTAssertEqual(savedTx.quantityChange, Decimal(-2))
    }
}
