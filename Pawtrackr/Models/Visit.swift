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
    var durationString: String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    /// Human‑readable date/time range for timeline rows.
    /// Examples:
    ///  - "Sep 5, 1:10 PM–2:30 PM" (same day, completed)
    ///  - "Sep 5, 1:10 PM–now"     (same day, active)
    ///  - "Sep 4, 11:50 PM – Sep 5, 12:15 AM" (spans days)
    var dateRangeString: String {
        let cal = Calendar.current
        let start = startedAt
        let end = endedAt
        
        let dateFormatter = DateFormatter()
        dateFormatter.locale = .current
        dateFormatter.timeZone = .current
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none
        
        let timeFormatter = DateFormatter()
        timeFormatter.locale = .current
        timeFormatter.timeZone = .current
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short
        
        // If start & end are the same calendar day, show: "Sep 5, 1:10 PM–2:30 PM"
        if let end, cal.isDate(start, inSameDayAs: end) {
            let day = dateFormatter.string(from: start)
            let startTime = timeFormatter.string(from: start)
            let endTime = timeFormatter.string(from: end)
            return "\(day), \(startTime)–\(endTime)"
        }
        
        // If still active, show "...–now"
        if endedAt == nil {
            let day = dateFormatter.string(from: start)
            let startTime = timeFormatter.string(from: start)
            return "\(day), \(startTime)–now"
        }
        
        // Spans multiple days; show full short date+time on both sides.
        let dtFormatter = DateFormatter()
        dtFormatter.locale = .current
        dtFormatter.timeZone = .current
        dtFormatter.dateStyle = .medium
        dtFormatter.timeStyle = .short
        
        let left = dtFormatter.string(from: start)
        let right = dtFormatter.string(from: endedAt!)
        return "\(left) – \(right)"
    }

    /// Sum of line items (snapshot math). Coalesces optional unitPrice to 0.
    var servicesSubtotal: Decimal {
        items.reduce(Decimal.zero) { acc, line in
            let price: Decimal = line.unitPrice ?? 0
            return acc + (price * Decimal(line.quantity))
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

    private func didUpdate() { updatedAt = .now }
}
