//
//  Visit.swift
//  Pawtrackr
//
//  Canonical Visit model for SwiftData
//

import Foundation
import SwiftData

@Model
final class Visit {
    // MARK: - Identity & Timestamps
    var uuid: UUID
    var createdAt: Date
    var updatedAt: Date
    var startedAt: Date
    var endedAt: Date?

    // MARK: - Notes & Media
    var note: String?
    @Attribute(.externalStorage) var beforePhotoData: Data?
    @Attribute(.externalStorage) var afterPhotoData: Data?

    // MARK: - Money
    /// Persisted grand total for this visit (non-optional, stored).
    /// IMPORTANT: do not duplicate/extend this with another property named `total`.
    var total: Decimal

    // MARK: - Relationships
    var pet: Pet

    @Relationship(deleteRule: .cascade, inverse: \VisitItem.visit)
    var items: [VisitItem] = []

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
        self.beforePhotoData = nil
        self.afterPhotoData = nil
        self.total = .zero
        self.pet = pet
    }

    // MARK: - Derived State
    var isActive: Bool { endedAt == nil }
    var isCompleted: Bool { endedAt != nil }
    var isPaid: Bool { payment != nil }

    var sortKeyDate: Date { endedAt ?? startedAt }

    /// Defensive duration (seconds)
    var duration: TimeInterval {
        let end = endedAt ?? .now
        return max(0, end.timeIntervalSince(startedAt))
    }
    
    /// Human-readable duration like "1h 23m" or "45m"
    @MainActor
    var durationString: String {
        Formatters.durationString(from: startedAt, to: endedAt ?? .now)
    }

    @MainActor
    var dateRangeString: String {
        Formatters.dateRangeString(from: startedAt, to: endedAt)
    }

    /// Sum of line items (snapshot math). Coalesces optional unitPrice to 0.
    var servicesSubtotal: Decimal {
        items.reduce(Decimal.zero) { acc, line in
            acc + (line.unitPrice * Decimal(line.quantity))
        }
    }

    /// While active use the running subtotal; once completed use persisted total
    var effectiveTotal: Decimal { isCompleted ? total : servicesSubtotal }

    // MARK: - Formatting helpers (assumes you have Decimal.moneyString)
    @MainActor var totalCurrencyString: String { effectiveTotal.moneyString }

    // MARK: - Operations
    
    func recalcTotal() {
        total = servicesSubtotal
        didUpdate()
    }

    func markCheckedIn(now: Date = .now) {
        if startedAt > now { startedAt = now }
        endedAt = nil
        didUpdate()
    }

    func markCheckedOut(total customTotal: Decimal? = nil, now: Date = .now) {
        if let custom = customTotal { total = custom.roundedMoney() } else { recalcTotal() }
        if endedAt == nil { endedAt = now }
        didUpdate()
    }

    // NEWLY ADDED: This function was missing, causing the build error in CheckoutViewModel.
    func applyPhotos(before: Data?, after: Data?) {
        self.beforePhotoData = before
        self.afterPhotoData = after
        didUpdate()
    }

    func addItem(title: String, unitPrice: Decimal?, quantity: Int = 1, service: Service? = nil) {
        let qty = max(1, quantity)
        let price = unitPrice ?? 0
        let item = VisitItem(name: title, unitPrice: price, quantity: qty, visit: self)
        item.service = service
        items.append(item)
        recalcTotal()
    }

    func removeItem(_ item: VisitItem) {
        if let idx = items.firstIndex(where: { $0 === item }) {
            items.remove(at: idx)
            recalcTotal()
        }
    }

    func attachPayment(_ payment: Payment) {
        self.payment = payment
        payment.visit = self
        didUpdate()
    }

    private func didUpdate() { 
        updatedAt = .now
        // Also update the client's last visit date to reflect the most recent activity.
        pet.owner?.lastVisitDate = sortKeyDate
    }
}
