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
    private let visitRepository: VisitRepositoryProtocol

    // MARK: - Outputs
    @Published var pets: [Pet] = []
    @Published var recentVisits: [Visit] = []
    @Published var historyRange: HistoryRange = .all { didSet { refreshRecentVisits() } }
    @Published private(set) var canLoadMore: Bool = false
    @Published var appError: AppError? = nil

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
        self.visitRepository = VisitRepository(modelContainer: modelContext.container)
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
        
        let petIDs = Set(client.pets.map { $0.persistentModelID })
        let now = Date()
        let cal = Calendar.current
        let startBound: Date? = {
            switch historyRange {
            case .all: return nil
            case .lastNDays(let days):
                return cal.date(byAdding: .day, value: -days, to: cal.startOfDay(for: now))
            }
        }()

        // Fetch most-recent visits for this client's pets using a predicate
        let descriptor = FetchDescriptor<Visit>(
            predicate: #Predicate<Visit> { v in
                if let endedAt = v.endedAt {
                    if let start = startBound {
                        return endedAt >= start
                    } else {
                        return true
                    }
                } else {
                    return false
                }
            },
            sortBy: [SortDescriptor(\.endedAt, order: .reverse)]
        )
        
        do {
            #if DEBUG
            let t0 = Date()
            #endif
            // We still fetch a bit more because we need to filter by pet identity in memory 
            // since SwiftData predicates have limitations with complex relationship filtering
            let results = try modelContext.fetch(descriptor)
            let filtered = results.filter { v in
                guard let pet = v.pet else { return false }
                return petIDs.contains(pet.persistentModelID)
            }
            
            self.lastTotalForClient = filtered.count
            self.canLoadMore = filtered.count > currentLimit
            self.recentVisits = Array(filtered.prefix(currentLimit))
            #if DEBUG
            let dt = Date().timeIntervalSince(t0)
            Logger.main.debug("Fetched client recent visits: total=\(self.lastTotalForClient), limit=\(self.currentLimit) in \(String(format: "%.2f", dt))s")
            #endif
        } catch {
            appError = .database(error.localizedDescription)
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
        
        Task {
            do {
                _ = try await visitRepository.checkIn(pet: pet, date: date)
                // Trigger UI refresh for pet cards and lists
                self.pets = client.pets
                objectWillChange.send()
            } catch {
                appError = .database(error.localizedDescription)
                Logger.main.error("Failed to check in: \(String(describing: error))")
            }
            refreshRecentVisits()
        }
    }

    func addService(_ service: Service, to visit: Visit, quantity: Int = 1) {
        visit.addItem(title: service.name, unitPrice: service.effectiveBasePrice, quantity: quantity, service: service)
        Task {
            do { 
                try await visitRepository.saveVisit(visit) 
            } catch {
                appError = .database(error.localizedDescription)
                Logger.main.error("Failed to add service: \(String(describing: error))")
            }
            refreshRecentVisits()
        }
    }

    func checkOut(pet: Pet, customTotal: Decimal? = nil, at date: Date = .now) {
        guard let visit = activeVisit(for: pet) else { return }
        
        Task {
            do {
                try await visitRepository.checkOut(visit: visit, total: customTotal, now: date)
                // Trigger UI refresh to flip buttons/timer state
                self.pets = client.pets
                objectWillChange.send()
            } catch {
                appError = .database(error.localizedDescription)
                Logger.main.error("Failed to check out: \(String(describing: error))")
            }
            refreshRecentVisits()
        }
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
