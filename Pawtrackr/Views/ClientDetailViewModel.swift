//
//  ClientDetailViewModel.swift
//  Pawtrackr
//
//  View-model for the Client Detail screen
//

import Foundation
import SwiftData
import Observation
import OSLog

@MainActor
final class ClientDetailViewModel: ObservableObject {
    // MARK: - Inputs
    let client: Client
    private let modelContext: ModelContext

    // MARK: - Outputs
    @Published var pets: [Pet] = []
    @Published var recentVisits: [Visit] = []
    @Published var historyRange: HistoryRange = .all { didSet { refreshRecentVisits() } }
    @Published private(set) var canLoadMore: Bool = false

    // Derived stats (avoid the name `total` here to prevent shadowing compiler weirdness)
    var visitCount: Int { recentVisits.count }
    var grandRevenue: Decimal { recentVisits.reduce(0) { $0 + $1.effectiveTotal } }

    // MARK: - Init
    // Paging configuration
    private let pageSize: Int = 50
    private var currentLimit: Int
    private var lastTotalForClient: Int = 0

    init(client: Client, modelContext: ModelContext, initialLimit: Int = 50) {
        self.client = client
        self.modelContext = modelContext
        self.pets = client.pets
        self.currentLimit = max(initialLimit, pageSize)
        refreshRecentVisits()
    }

    // MARK: - Queries
    func activeVisit(for pet: Pet) -> Visit? {
        // Simple in-memory check first
        return pet.visits.first(where: { $0.endedAt == nil })
    }

    func refreshRecentVisits(limit: Int? = nil) {
        if let limit { currentLimit = max(limit, pageSize) }
        // Fetch most-recent visits globally, then filter to this client's pets for portability across stores
        var descriptor = FetchDescriptor<Visit>(
            sortBy: [SortDescriptor(\.endedAt, order: .reverse)]
        )
        // Avoid materializing the entire Visit table; we need just a window
        descriptor.fetchLimit = max(currentLimit * 10, pageSize * 10)
        do {
            #if DEBUG
            let t0 = Date()
            #endif
            let results = try modelContext.fetch(descriptor)
            let allowedPetIDs = Set(client.pets.map { $0.persistentModelID })
            let now = Date()
            let cal = Calendar.current
            let startBound: Date? = {
                switch historyRange {
                case .all: return nil
                case .lastNDays(let days):
                    return cal.date(byAdding: .day, value: -days, to: cal.startOfDay(for: now))
                }
            }()
            let filtered = results.filter { v in
                guard v.endedAt != nil else { return false }
                guard allowedPetIDs.contains(v.pet.persistentModelID) else { return false }
                if let start = startBound, let ended = v.endedAt { return ended >= start }
                return true
            }
            self.lastTotalForClient = filtered.count
            self.canLoadMore = filtered.count > currentLimit
            self.recentVisits = Array(filtered.prefix(currentLimit))
            #if DEBUG
            let dt = Date().timeIntervalSince(t0)
            Logger.main.debug("Fetched client recent visits: total=\(self.lastTotalForClient), limit=\(self.currentLimit) in \(String(format: "%.2f", dt))s")
            #endif
        } catch {
            Logger.main.error("Failed to fetch recent visits: \(String(describing: error))")
            self.recentVisits = []
            self.canLoadMore = false
        }
    }

    func loadMore() {
        currentLimit += pageSize
        refreshRecentVisits()
    }

    // MARK: - Types
    enum HistoryRange: Hashable {
        case all
        case lastNDays(Int)
    }

    // MARK: - Actions
    func checkIn(pet: Pet, at date: Date = .now) {
        // If already active, no-op
        if activeVisit(for: pet) != nil { return }
        let v = Visit(pet: pet, startedAt: date)  // ✅ provide required 'pet'
        modelContext.insert(v)
        do {
            try modelContext.save()
            // Trigger UI refresh for pet cards and lists
            self.pets = client.pets
            objectWillChange.send()
        } catch {
            Logger.main.error("Failed to check in: \(String(describing: error))")
        }
        refreshRecentVisits()
    }

    func addService(_ service: Service, to visit: Visit, quantity: Int = 1) {
        visit.addItem(title: service.name, unitPrice: service.basePrice, quantity: quantity, service: service)
        do { try modelContext.save() } catch {
            Logger.main.error("Failed to add service: \(String(describing: error))")
        }
        refreshRecentVisits()
    }

    func checkOut(pet: Pet, customTotal: Decimal? = nil, at date: Date = .now) {
        guard let visit = activeVisit(for: pet) else { return }
        visit.markCheckedOut(total: customTotal, now: date)
        do {
            try modelContext.save()
            // Trigger UI refresh to flip buttons/timer state
            self.pets = client.pets
            objectWillChange.send()
            // Update per-day summaries for Insights
            if let ended = visit.endedAt {
                SummaryUpdater.rebuildDay(for: ended, in: modelContext)
            }
        } catch {
            Logger.main.error("Failed to check out: \(String(describing: error))")
        }
        refreshRecentVisits()
        NotificationCenter.default.postVisitDidComplete(metadata: VisitDidCompleteMetadata(visit: visit))
    }

    /// Freezes the active visit's timer by setting `endedAt` to the provided date.
    /// Does not attach payment or change totals. Checkout will finalize totals/payment.
    @available(*, deprecated, message: "Freezing now occurs centrally when entering Checkout.")
    func pauseVisitForCheckout(pet: Pet, at date: Date = .now) {
        // No-op. Use Checkout flow to freeze at entry.
    }
}

// Shared helpers (kept here for now; move to your common helpers files if you prefer)
extension Logger { static let main = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "ClientDetail") }
