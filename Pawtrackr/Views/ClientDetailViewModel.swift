//
//  ClientDetailViewModel.swift
//  Pawtrackr
//
//  Created by mac on 9/3/25.
//

import Foundation
import SwiftUI
import SwiftData
import OSLog

@MainActor
final class ClientDetailViewModel: ObservableObject {
    // MARK: - Inputs / Environment
    private let modelContext: ModelContext
    private let log = Logger.main

    // MARK: - Backing Model
    @Published var client: Client

    // MARK: - Derived Collections
    @Published private(set) var pets: [Pet] = []
    @Published private(set) var recentVisits: [Visit] = []

    // MARK: - Stats
    struct Stats: Equatable {
        var visitsCount: Int = 0
        var totalSpent: Decimal = .zero
        var averageDuration: TimeInterval = 0

        var averageDurationString: String {
            Self.durationString(from: averageDuration)
        }

        var totalSpentString: String { totalSpent.moneyString }

        static func durationString(from interval: TimeInterval) -> String {
            let totalMinutes = max(0, Int(interval / 60))
            let h = totalMinutes / 60
            let m = totalMinutes % 60
            return h > 0 ? "\(h)h \(m)m" : "\(m)m"
        }
    }

    @Published private(set) var stats: Stats = .init()

    // MARK: - Init
    init(client: Client, modelContext: ModelContext) {
        self.client = client
        self.modelContext = modelContext
        Task { await refresh() }
    }

    // MARK: - Public API

    /// Refreshes pets, recent visits, and stats for the current client.
    func refresh() async {
        await fetchPets()
        await fetchRecentVisits()
        computeStats()
    }

    /// Returns the active (in-progress) visit for a given pet, if any.
    func activeVisit(for pet: Pet) -> Visit? {
        pet.visits.first(where: { $0.endedAt == nil })
    }

    /// Starts a new visit for the given pet if one is not already active.
    @discardableResult
    func checkIn(pet: Pet, at date: Date = .now) -> Visit? {
        if let existing = activeVisit(for: pet) { return existing }
        let visit = Visit(startedAt: date)
        visit.pet = pet
        // ensure relationship integrity
        pet.visits.append(visit)
        modelContext.insert(visit)
        do {
            try modelContext.save()
            log.info("Started visit for pet: \(pet.name, privacy: .public)")
            return visit
        } catch {
            log.error("Failed to start visit: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Ends the current visit for the pet, optionally attaching a payment. Posts `.visitDidComplete` on success.
    func checkOut(pet: Pet, at date: Date = .now, attachPayment: ((Visit) -> Void)? = nil) {
        guard let visit = activeVisit(for: pet) else { return }
        visit.endedAt = max(visit.startedAt, date)
        // Allow caller (CheckoutViewModel) to attach payment, items, tips, etc.
        attachPayment?(visit)
        do {
            try modelContext.save()
            log.info("Completed visit for pet: \(pet.name, privacy: .public)")
            NotificationCenter.default.post(name: .visitDidComplete, object: visit)
            Task { await refresh() }
        } catch {
            log.error("Failed to complete visit: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Private Fetch Helpers

    private func fetchPets() async {
        // If relationship is already loaded, prefer it
        if !client.pets.isEmpty {
            pets = client.pets.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            return
        }
        // Fallback explicit fetch (in case the relationship is not loaded yet)
        let descriptor = FetchDescriptor<Pet>(
            predicate: #Predicate { $0.owner?.id == client.id },
            sortBy: [SortDescriptor(\.name, order: .forward)]
        )
        do {
            pets = try modelContext.fetch(descriptor)
        } catch {
            log.error("Failed to fetch pets: \(error.localizedDescription, privacy: .public)")
            pets = []
        }
    }

    private func fetchRecentVisits(limit: Int = 50) async {
        // Pull by owner via pet.owner relationship
        let descriptor = FetchDescriptor<Visit>(
            predicate: #Predicate { $0.pet?.owner?.id == client.id },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        do {
            let fetched = try modelContext.fetch(descriptor)
            recentVisits = Array(fetched.prefix(limit))
        } catch {
            log.error("Failed to fetch visits: \(error.localizedDescription, privacy: .public)")
            recentVisits = []
        }
    }

    private func computeStats() {
        let visits = recentVisits
        let ended = visits.compactMap { v -> (TimeInterval, Decimal)? in
            guard let end = v.endedAt else { return nil }
            let dur = max(0, end.timeIntervalSince(v.startedAt))
            // Prefer stored total if present, else compute from items
            let amount: Decimal = v.total ?? v.items.reduce(.zero) { $0 + ($1.unitPrice * Decimal($1.quantity)) }
            return (dur, amount)
        }

        let count = visits.count
        let totalSpent = ended.reduce(.zero) { $0 + $1.1 }
        let totalDuration = ended.reduce(0) { $0 + $1.0 }
        let averageDuration = count > 0 ? totalDuration / Double(max(1, count)) : 0

        stats = .init(visitsCount: count, totalSpent: totalSpent, averageDuration: averageDuration)
    }
}

// MARK: - Minimal model shims used by the view model
// These extend your existing @Model types without redefining them.
extension Visit {
    /// Stored total if your model has it; otherwise this returns nil and the VM will compute from items.
    var total: Decimal? { (self as AnyObject).value(forKey: "total") as? Decimal }
}
