//
//  VisitItem.swift
//  Pawtrackr
//
//  Created by mac on 8/17/25.
//  Join model for per-visit line items (snapshot of Service + optional overrides)

import SwiftUI
import Foundation
import SwiftData

/// A single line item on a Visit (e.g., "Bath", "Haircut").
///
/// Notes
/// - This model intentionally avoids public access modifiers and model-specific
///   types in any public API to prevent visibility errors ("public uses internal type").
/// - Deletion cascade should be declared on the owning side (Visit.items with
///   `@Relationship(deleteRule: .cascade)`), to ensure deleting a Visit removes its items.
@Model
final class VisitItem: Identifiable, ObservableObject {
    // MARK: Identity & Timestamps
    @Attribute(.unique) var uuid: UUID
    var createdAt: Date
    var updatedAt: Date

    // MARK: Relationships
    /// Owning visit. The inverse should be declared on Visit:
    /// `@Relationship(deleteRule: .cascade, inverse: \VisitItem.visit) var items: [VisitItem] = []`
    @Relationship var visit: Visit

    /// The source service for this item (optional so we can keep a snapshot even if Service is deleted/renamed).
    @Relationship var service: Service?

    // MARK: Snapshot & Overrides
    /// Snapshot of the service display name at the time of checkout.
    var name: String { didSet { updatedAt = Date() } }

    /// Unit price for this line item (override). If nil, falls back to the service default price.
    var unitPrice: Decimal? { didSet { updatedAt = Date() } }

    /// Quantity for this line item (defaults to 1).
    var quantity: Int { didSet { updatedAt = Date() } }

    /// Optional note for this line item (e.g., "matted fur surcharge").
    var note: String?

    /// Back‑compat alias for older code that used `price`.
    var price: Decimal? {
        get { unitPrice }
        set { unitPrice = newValue }
    }

    // MARK: Derived
    /// Effective **unit** price used for totals: override -> service.defaultPrice -> 0.
    var effectivePrice: Decimal {
        if let unitPrice { return unitPrice }
        if let svc = service, let def = svc.defaultPrice { return def }
        return 0
    }

    /// Line total = unit price × quantity.
    var lineTotal: Decimal {
        effectivePrice * Decimal(quantity)
    }

    /// Formatted USD price for UI.
    var formattedPriceUSD: String {
        NumberFormatters.usd.string(from: NSDecimalNumber(decimal: effectivePrice)) ?? "$0.00"
    }

    /// Convenience cents accessors for integrations that prefer integer math (line total).
    var amountCents: Int { NSDecimalNumber(decimal: lineTotal * 100).intValue }

    /// Convenience formatted price property
    var formattedPrice: String {
        NumberFormatter.localizedString(from: NSNumber(value: (price as NSDecimalNumber?)?.doubleValue ?? 0.0), number: .currency)
    }

    // MARK: Init
    init(service: Service, price: Decimal? = nil, note: String? = nil, visit: Visit) {
        self.uuid = UUID()
        self.createdAt = Date()
        self.updatedAt = Date()
        self.service = service
        self.visit = visit
        self.name = service.name
        self.unitPrice = price
        self.quantity = 1
        self.note = note
    }

    /// Create directly from a name (if the Service is optional/unknown at creation time).
    init(name: String, price: Decimal? = nil, note: String? = nil, visit: Visit, service: Service? = nil) {
        self.uuid = UUID()
        self.createdAt = Date()
        self.updatedAt = Date()
        self.service = service
        self.visit = visit
        self.name = name
        self.unitPrice = price
        self.quantity = 1
        self.note = note
    }

    /// Convenience initializer matching call sites that pass visit first.
    convenience init(visit: Visit, service: Service, name: String, price: Decimal? = nil, note: String? = nil) {
        self.init(name: name, price: price, note: note, visit: visit, service: service)
    }

    // MARK: Mutation helpers
    func overridePrice(_ newPrice: Decimal?) { self.price = newPrice; touch() }
    func setNote(_ new: String?) { self.note = new; touch() }
    func touch() { self.updatedAt = Date() }
}

// MARK: - Local formatters (USD only)
private enum NumberFormatters {
    static let usd: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.locale = .autoupdatingCurrent
        f.generatesDecimalNumbers = true
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()
}

// MARK: - Preview Seeds
#if DEBUG
extension VisitItem {
    static func preview(_ name: String, dollars: Decimal, note: String? = nil) -> VisitItem {
        VisitItem(name: name, price: dollars, note: note, visit: Visit.preview)
    }
}
#endif
