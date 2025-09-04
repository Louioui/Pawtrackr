//
//  Visit.swift
//  Pawtrackr
//
//  Created by mac on 8/14/25.
//  Updated by Assistant on 2025-09-03.
//

import Foundation
import SwiftData

@Model
final class Visit {
    // MARK: - Core Fields
    var uuid: UUID
    var createdAt: Date
    var updatedAt: Date
    var startedAt: Date
    var endedAt: Date?
    var note: String?
    /// Persisted grand total for a completed visit. While in progress, derive from items.
    var total: Decimal

    // Store large blobs externally
    @Attribute(.externalStorage) var beforePhotoData: Data?
    @Attribute(.externalStorage) var afterPhotoData: Data?

    // MARK: - Relationships
    /// Owning pet for this visit
    var pet: Pet

    /// Line items captured for this visit. Owner side keeps @Relationship; inverse lives on VisitItem as `var visit: Visit` (no macro).
    @Relationship(deleteRule: .cascade, inverse: \VisitItem.visit)
    var items: [VisitItem] = []

    /// Optional payment associated with this visit. Inverse lives on Payment as `var visit: Visit?` (no macro on that side).
    @Relationship(deleteRule: .cascade, inverse: \Payment.visit)
    var payment: Payment?

    // MARK: - Init
    init(pet: Pet, startedAt: Date = .now) {
        self.uuid = UUID()
        self.createdAt = .now
        self.updatedAt = .now
        self.startedAt = startedAt
        self.endedAt = nil
        self.note = nil
        self.total = .zero
        self.pet = pet
    }

    // MARK: - Derived State
    var isActive: Bool { endedAt == nil }
    var isCompleted: Bool { endedAt != nil }
    var isPaid: Bool { payment != nil }

    /// Sort key used by lists (prefer end date, else now while active)
    var sortKeyDate: Date { endedAt ?? .now }

    /// Defensive duration in seconds (never negative)
    var duration: TimeInterval {
        let end = endedAt ?? .now
        return max(0, end.timeIntervalSince(startedAt))
    }

    /// Sum of line items (used while visit is in progress or as a fallback)
    var servicesSubtotal: Decimal {
        items.reduce(Decimal.zero) { partial, line in
            partial + (line.unitPrice * Decimal(line.quantity))
        }
    }

    // MARK: - UI Formatting (MainActor to avoid actor-isolation warnings)
    @MainActor
    var dateRangeString: String {
        Formatters.dateRangeString(from: startedAt, to: endedAt ?? .now)
    }

    @MainActor
    var durationString: String {
        Formatters.durationString(from: startedAt, to: endedAt ?? .now)
    }

    @MainActor
    var totalCurrencyString: String {
        let amount = isCompleted ? total : servicesSubtotal
        return amount.moneyString
    }

    // MARK: - Business Logic
    /// Recalculate and store the visit grand total from items. Call on any items mutation.
    func recalcTotal() {
        total = servicesSubtotal
        didUpdate()
    }

    /// Mark the visit as checked out. If a custom total is provided (after tips/discounts), it wins; otherwise we sum items.
    func markCheckedOut(total customTotal: Decimal? = nil, now: Date = .now) {
        if let custom = customTotal { total = custom.roundedMoney() } else { recalcTotal() }
        if endedAt == nil { endedAt = now }
        didUpdate()
    }

    /// Attach a line item (snapshots name & price so history remains stable if the catalog changes).
    func addItem(title: String, unitPrice: Decimal, quantity: Int = 1, service: Service? = nil) {
        let qty = max(1, quantity)
        let item = VisitItem(name: title, unitPrice: max(0, unitPrice), quantity: qty, visit: self)
        item.service = service
        items.append(item)
        recalcTotal()
    }

    /// Remove a specific item instance.
    func removeItem(_ item: VisitItem) {
        if let idx = items.firstIndex(where: { $0 === item }) {
            items.remove(at: idx)
            recalcTotal()
        }
    }

    /// Attach a payment (e.g., after checkout confirm)
    func attachPayment(_ payment: Payment) {
        self.payment = payment
        payment.visit = self
        didUpdate()
    }

    // MARK: - Internal
    private func didUpdate() {
        updatedAt = .now
    }
}
