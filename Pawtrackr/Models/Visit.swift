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
    // NOTE: Non-optional properties have defaults for CloudKit compatibility.
    var uuid: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var startedAt: Date = Date()
    var endedAt: Date?
    var lastModifiedBy: UUID = DeviceIdentity.currentID
    var lastModifiedAt: Date = Date()

    // MARK: - Notes & Media
    var note: String?
    var behaviorTagsRaw: String = ""
    @Transient
    var behaviorTags: [String] {
        get { Self.decodeBehaviorTags(from: behaviorTagsRaw) }
        set { behaviorTagsRaw = Self.encodeBehaviorTags(newValue) }
    }
    @Attribute(.externalStorage) var beforePhotoData: Data?
    @Attribute(.externalStorage) var afterPhotoData: Data?
    @Attribute(.externalStorage) var beforeThumbnailData: Data?
    @Attribute(.externalStorage) var afterThumbnailData: Data?

    // MARK: - Money
    /// Persisted grand total for this visit (non-optional, stored).
    /// IMPORTANT: do not duplicate/extend this with another property named `total`.
    var total: Decimal = Decimal.zero

    // MARK: - Relationships
    /// The pet this visit belongs to. Optional to allow SwiftData cascade deletes to work properly.
    var pet: Pet?

    @Relationship(deleteRule: .cascade, inverse: \VisitItem.visit)
    var items: [VisitItem]? = []

    @Relationship(deleteRule: .cascade, inverse: \Payment.visit)
    var payment: Payment?
    
    @Relationship(deleteRule: .nullify, inverse: \Appointment.visit)
    var appointment: Appointment?
    
    var user: User?

    // MARK: - Init
    init(pet: Pet, startedAt: Date = .now) {
        self.uuid = UUID()
        self.createdAt = .now
        self.updatedAt = .now
        self.startedAt = startedAt
        self.endedAt = nil
        self.lastModifiedBy = DeviceIdentity.currentID
        self.lastModifiedAt = .now
        self.note = nil
        self.beforePhotoData = nil
        self.afterPhotoData = nil
        self.total = .zero
        self.pet = pet
    }

    /// Convenience initializer when pet may not be available yet
    init(startedAt: Date = .now) {
        self.uuid = UUID()
        self.createdAt = .now
        self.updatedAt = .now
        self.startedAt = startedAt
        self.endedAt = nil
        self.lastModifiedBy = DeviceIdentity.currentID
        self.lastModifiedAt = .now
        self.note = nil
        self.beforePhotoData = nil
        self.afterPhotoData = nil
        self.total = .zero
        self.pet = nil
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
    @MainActor var durationString: String {
        Formatters.durationString(from: startedAt, to: endedAt ?? .now)
    }

    @MainActor var dateRangeString: String {
        Formatters.dateRangeString(from: startedAt, to: endedAt)
    }

    /// Sum of line items (snapshot math). Coalesces optional unitPrice to 0.
    var servicesSubtotal: Decimal {
        (items ?? []).reduce(Decimal.zero) { acc, line in
            acc + (line.unitPrice * Decimal(line.quantity))
        }
    }

    /// Calculates the total from line items.
    var calculatedTotal: Decimal {
        servicesSubtotal.roundedMoney()
    }

    /// While active use the calculated total; once completed use persisted total
    var effectiveTotal: Decimal { isCompleted ? total : calculatedTotal }

    // MARK: - Formatting helpers (assumes you have Decimal.moneyString)
    @MainActor var totalCurrencyString: String { effectiveTotal.moneyString }

    // MARK: - Operations
    
    func recalcTotal() {
        total = calculatedTotal
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

    /// Store pre-processed photo data. Callers must downsample off the main thread before calling.
    func applyPhotos(before: Data?, beforeThumb: Data?, after: Data?, afterThumb: Data?) {
        self.beforePhotoData = before
        self.beforeThumbnailData = beforeThumb
        self.afterPhotoData = after
        self.afterThumbnailData = afterThumb
        didUpdate()
    }

    func addItem(title: String, unitPrice: Decimal?, quantity: Int = 1, service: Service? = nil) {
        let qty = max(1, quantity)
        let price = unitPrice ?? 0
        let item = VisitItem(name: title, unitPrice: price, quantity: qty, visit: self)
        item.service = service
        var currentItems = items ?? []
        currentItems.append(item)
        items = currentItems
        recalcTotal()
    }

    func removeItem(_ item: VisitItem) {
        var currentItems = items ?? []
        if let idx = currentItems.firstIndex(where: { $0 === item }) {
            currentItems.remove(at: idx)
            items = currentItems
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
        lastModifiedBy = DeviceIdentity.currentID
        lastModifiedAt = updatedAt
        // Only attempt to update the client's last visit date if we can safely reach it.
        // In background contexts, we avoid forcing a load of the entire owner hierarchy.
        if let owner = pet?.owner {
            owner.lastVisitDate = sortKeyDate
        }
    }

    private static func decodeBehaviorTags(from raw: String) -> [String] {
        guard !raw.isEmpty, let data = raw.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    private static func encodeBehaviorTags(_ tags: [String]) -> String {
        let cleaned = tags.map { $0.trimmed }.filter { !$0.isEmpty }
        guard let data = try? JSONEncoder().encode(cleaned),
              let raw = String(data: data, encoding: .utf8) else {
            return ""
        }
        return raw
    }
}
