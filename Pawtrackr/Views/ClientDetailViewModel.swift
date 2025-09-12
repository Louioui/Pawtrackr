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

    // Derived stats (avoid the name `total` here to prevent shadowing compiler weirdness)
    var visitCount: Int { recentVisits.count }
    var grandRevenue: Decimal { recentVisits.reduce(0) { $0 + $1.effectiveTotal } }

    // MARK: - Init
    init(client: Client, modelContext: ModelContext) {
        self.client = client
        self.modelContext = modelContext
        self.pets = client.pets
        refreshRecentVisits()
    }

    // MARK: - Queries
    func activeVisit(for pet: Pet) -> Visit? {
        // Simple in-memory check first
        return pet.visits.first(where: { $0.endedAt == nil })
    }

    func refreshRecentVisits(limit: Int = 50) {
        // Fetch most-recent visits, then filter in-memory for portability
        let descriptor = FetchDescriptor<Visit>(
            sortBy: [SortDescriptor(\.endedAt, order: .reverse)]
        )
        do {
            let results = try modelContext.fetch(descriptor)
            let allowedPetIDs = Set(client.pets.map { $0.persistentModelID })
            let filtered = results.filter { v in
                v.endedAt != nil && allowedPetIDs.contains(v.pet.persistentModelID)
            }
            self.recentVisits = Array(filtered.prefix(limit))
        } catch {
            Logger.main.error("Failed to fetch recent visits: \(String(describing: error))")
            self.recentVisits = []
        }
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
        } catch {
            Logger.main.error("Failed to check out: \(String(describing: error))")
        }
        refreshRecentVisits()
        NotificationCenter.default.post(name: .visitDidComplete, object: visit)
    }

    /// Freezes the active visit's timer by setting `endedAt` to the provided date.
    /// Does not attach payment or change totals. Checkout will finalize totals/payment.
    func pauseVisitForCheckout(pet: Pet, at date: Date = .now) {
        guard let visit = activeVisit(for: pet), visit.endedAt == nil else { return }
        visit.endedAt = date
        do {
            try modelContext.save()
            // Trigger UI refresh (pet goes from active → completed (unpaid))
            self.pets = client.pets
            objectWillChange.send()
        } catch {
            Logger.main.error("Failed to freeze visit before checkout: \(String(describing: error))")
        }
    }
}

// Shared helpers (kept here for now; move to your common helpers files if you prefer)
extension Logger { static let main = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "ClientDetail") }
