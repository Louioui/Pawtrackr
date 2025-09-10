//
//  VisitItem.swift
//  Pawtrackr
//
//  Created by mac on 8/17/25.
//  Updated by Assistant on 2025-09-03.
//

import Foundation
import SwiftData

/// A single line item on a Visit, representing a snapshot of a service at the time of the visit.
/// This ensures historical accuracy even if the original Service in the catalog is changed or deleted.
@Model
final class VisitItem {
    // MARK: - Properties
    @Attribute(.unique) var uuid: UUID
    var createdAt: Date
    var updatedAt: Date

    /// The name of the service, captured at the time the item was created.
    @Attribute var name: String
    
    /// The price for a single unit of this service, captured at the time the item was created.
    var unitPrice: Decimal
    
    /// The quantity of this service provided. Must be at least 1.
    var quantity: Int
    
    /// Optional notes specific to this line item.
    var note: String?

    // MARK: - Relationships
    
    /// The `Visit` this line item belongs to. If the visit is deleted, this item is also deleted.
    // FIX: The inverse side of a relationship is a plain property with NO @Relationship macro.
    // This resolves the "circular reference" build error.
    var visit: Visit
    
    /// An optional link to the original `Service` in the catalog.
    /// If the `Service` is deleted, this link becomes `nil` but the historical record remains.
    @Relationship(deleteRule: .nullify) var service: Service?

    // MARK: - Initializers
    
    /// Creates a line item by snapshotting a `Service` from the catalog.
    private init(service: Service, priceOverride: Decimal? = nil, note: String? = nil, visit: Visit) {
        self.uuid = UUID()
        self.createdAt = .now
        self.updatedAt = .now
        self.service = service
        self.visit = visit
        self.name = service.name.trimmed
        self.unitPrice = (priceOverride ?? service.effectiveBasePrice).roundedMoney()
        self.quantity = 1
        self.note = note
    }

    /// Creates a custom line item that does not link to a catalog `Service`.
    init(name: String, unitPrice: Decimal, quantity: Int = 1, note: String? = nil, visit: Visit) {
        self.uuid = UUID()
        self.createdAt = .now
        self.updatedAt = .now
        self.service = nil
        self.visit = visit
        self.name = name.trimmed
        self.unitPrice = unitPrice.roundedMoney()
        self.quantity = max(1, quantity)
        self.note = note
    }

    // MARK: - Factory
    
    /// The preferred factory method for creating a `VisitItem` from a catalog `Service`.
    static func from(service: Service,
                     visit: Visit,
                     quantity: Int = 1,
                     priceOverride: Decimal? = nil,
                     note: String? = nil) -> VisitItem {
        let item = VisitItem(service: service, priceOverride: priceOverride, note: note, visit: visit)
        item.quantity = max(1, quantity)
        return item
    }

    // MARK: - Mutating API
    func setName(_ newName: String) {
        self.name = newName.trimmed
        didUpdate()
    }

    func setUnitPrice(_ newPrice: Decimal) {
        self.unitPrice = newPrice.roundedMoney()
        didUpdate()
    }

    func setQuantity(_ newQuantity: Int) {
        self.quantity = max(1, newQuantity)
        didUpdate()
    }

    // MARK: - Derived Properties & Formatting
    
    var lineTotal: Decimal {
        (unitPrice * Decimal(quantity)).roundedMoney()
    }
    
    @MainActor
    var unitPriceString: String {
        unitPrice.moneyString
    }
    
    @MainActor
    var lineTotalString: String {
        lineTotal.moneyString
    }
    
    @MainActor
    var receiptLine: String {
        let qtyString = quantity > 1 ? " ×\(quantity)" : ""
        return "\(name)\(qtyString) • \(lineTotalString)"
    }

    var displayName: String { name }

    private func didUpdate() {
        updatedAt = .now
    }
}

// FIX: Add local extensions to resolve 'trimmed' and 'roundedMoney' being inaccessible.
// A better long-term solution is to move these to their own shared files.

fileprivate extension Decimal {
    func roundedMoney() -> Decimal {
        var result = Decimal()
        var value = self
        NSDecimalRound(&result, &value, 2, .bankers)
        return result
    }
}
