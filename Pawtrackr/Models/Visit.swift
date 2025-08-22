//
//  Visit.swift
//  Pawtrackr
//
//  A grooming visit for a specific pet. Tracks timing, items, notes, total,
//  and optional payment. Used by RecentHistoryView, PetHistoryView, Checkout, etc.
//
//  Created by mac on 8/14/25.
//  Updated by mac on 8/17/25.
//

import Foundation
import SwiftData

@Model
final class Visit {
    // MARK: - Identity & timestamps
    @Attribute(.unique) var uuid: UUID
    var createdAt: Date
    var updatedAt: Date

    // MARK: - Session timing
    var startedAt: Date { didSet { updatedAt = Date() } }
    var endedAt: Date? { didSet { updatedAt = Date() } }

    // MARK: - Details
    var notes: String? { didSet { updatedAt = Date() } }
    var total: Decimal { didSet { updatedAt = Date() } }
    @Attribute(.externalStorage) var beforePhotoData: Data? { didSet { updatedAt = Date() } }
    @Attribute(.externalStorage) var afterPhotoData: Data? { didSet { updatedAt = Date() } }

    /// Backwards‑compat alias used by older ViewModels
    var photoBefore: Data? {
        get { beforePhotoData }
        set { beforePhotoData = newValue }
    }

    /// Backwards‑compat alias used by older ViewModels
    var photoAfter: Data? {
        get { afterPhotoData }
        set { afterPhotoData = newValue }
    }

    // MARK: - Relations
    @Relationship var pet: Pet
    @Relationship(deleteRule: .cascade, inverse: \VisitItem.visit) var items: [VisitItem] = [] { didSet { updatedAt = Date() } }
    @Relationship(deleteRule: .cascade) var payment: Payment?

    // MARK: - Init
    init(pet: Pet,
         startedAt: Date = Date(),
         endedAt: Date? = nil,
         notes: String? = nil,
         total: Decimal = 0,
         items: [VisitItem] = [],
         payment: Payment? = nil) {
        self.uuid = UUID()
        self.createdAt = Date()
        self.updatedAt = Date()
        self.pet = pet
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.notes = notes
        self.total = total
        self.items = items
        self.payment = payment
    }

    // MARK: - Derived
    var isActive: Bool { endedAt == nil }
    
    /// Live total from items (sum of prices) while the visit is in progress.
    var runningTotal: Decimal { items.reduce(0) { $0 + ($1.price ?? 0) } }
    
    private enum Formatters {
        static let currency: NumberFormatter = {
            let nf = NumberFormatter()
            nf.numberStyle = .currency
            nf.currencyCode = "USD"
            nf.locale = .autoupdatingCurrent
            nf.minimumFractionDigits = 2
            nf.maximumFractionDigits = 2
            return nf
        }()
    }
    
    /// Always display totals in USD for the USA use‑case.
    var totalUSDString: String {
        Formatters.currency.string(from: NSDecimalNumber(decimal: total)) ?? "$0.00"
    }
    
    /// Whether the visit has a recorded payment timestamp.
    var isPaid: Bool { payment?.paidAt != nil }
    
    /// The effective end date used for sorting (endedAt if present, else startedAt).
    var sortKeyDate: Date { endedAt ?? startedAt }
    
    /// Unified date used for comparisons
    var endOrStart: Date { endedAt ?? startedAt }
    
    /// Sort helper: most‑recent visits first (endedAt if available, otherwise startedAt).
    static func mostRecentFirst(_ lhs: Visit, _ rhs: Visit) -> Bool {
        lhs.endOrStart > rhs.endOrStart
    }

    var durationSeconds: Int {
        let end = endedAt ?? Date()
        return max(0, Int(end.timeIntervalSince(startedAt)))
    }

    var durationString: String {
        let s = durationSeconds
        let h = s / 3600
        let m = (s % 3600) / 60
        let remS = s % 60
        if h > 0 { return String(format: "%dh %dm", h, m) }
        if m > 0 { return String(format: "%dm", m) }
        return String(format: "%ds", remS)
    }

    /// Names of line items for quick display/search
    var itemNames: [String] { items.map { $0.name } }
    
    /// Live view into the underlying services referenced by items (if still present)
    var services: [Service] { items.compactMap { $0.service } }

    /// Append a VisitItem built from a Service snapshot and keep totals updated.
    @discardableResult
    func addItem(from service: Service, priceOverride: Decimal? = nil, quantity: Int = 1) -> VisitItem {
        let item = VisitItem(visit: self, service: service, name: service.name)
        item.unitPrice = priceOverride ?? service.defaultPrice
        item.quantity = max(1, quantity)
        items.append(item)
        recalcTotal()
        return item
    }

    /// Replace current items with snapshots from a Service catalog (name + price only)
    func snapshotItems(from services: [Service]) {
        items.removeAll()
        for svc in services { _ = addItem(from: svc) }
    }

    /// Set before/after photos in one call
    func applyPhotos(before: Data?, after: Data?) {
        beforePhotoData = before
        afterPhotoData = after
        touch()
    }

    /// Recalculate and persist the visit's total from its items.
    func recalcTotal() {
        let sum = items.reduce(Decimal.zero) { partial, item in
            partial + (item.price ?? .zero)
        }
        total = sum
        touch()
    }

    func touch() { updatedAt = Date() }
    
    /// Mark the visit as started "now" (resets any previous end time).
    func markCheckedIn(now: Date = .now) {
        startedAt = now
        endedAt = nil
        touch()
    }
    
    /// Mark the visit as ended and persist a final total (still USD).
    func markCheckedOut(total amount: Decimal, now: Date = .now) {
        total = (amount > 0) ? amount : runningTotal
        endedAt = now
        touch()
    }
}

#if DEBUG
import Foundation

extension Client {
    static var preview: Client {
        Client(firstName: "Alex", lastName: "Rivera")
    }
}

extension Pet {
    static var preview: Pet {
        let client = Client.preview
        // Create a Pet using the simplest initializer available, then assign fields.
        let pet = Pet(name: "Milo", species: .dog)
        pet.gender = .male
        pet.owner = client
        return pet
    }
}

extension Visit {
    static var preview: Visit {
        let pet = Pet.preview
        return Visit(pet: pet, startedAt: Date().addingTimeInterval(-3600))
    }
}
#endif
