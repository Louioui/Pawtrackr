import Foundation
import SwiftData

@Model
final class InventoryItem {
    var uuid: UUID = UUID()
    var name: String = ""
    var category: String = ""
    var currentStock: Double = 0.0
    var unit: String = "" // e.g., "Gallons", "Bottles", "Sets"
    var reorderLevel: Double = 5.0
    var costPerUnit: Decimal = 0.0
    
    @Relationship(deleteRule: .cascade, inverse: \InventoryTransaction.item) 
    var transactions: [InventoryTransaction]? = []

    init(name: String, category: String, unit: String, costPerUnit: Decimal) {
        self.uuid = UUID()
        self.name = name
        self.category = category
        self.unit = unit
        self.costPerUnit = costPerUnit
    }
}

@Model
final class InventoryTransaction {
    var uuid: UUID = UUID()
    var date: Date = Date()
    var quantityChange: Double = 0.0 // Negative for usage, positive for restock
    var note: String? = ""
    
    var item: InventoryItem?

    init(item: InventoryItem, quantityChange: Double, note: String? = nil) {
        self.uuid = UUID()
        self.date = Date()
        self.item = item
        self.quantityChange = quantityChange
        self.note = note
    }
}
