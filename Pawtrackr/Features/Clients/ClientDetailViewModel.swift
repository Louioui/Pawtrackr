//
//  ClientDetailViewModel.swift
//  Pawtrackr
//
//  Converted to @Observable so that @State var viewModel in ClientDetailView
//  correctly observes property changes.
//  refreshRecentVisits() now performs the heavy DB fetch on a background context
//  to prevent blocking the main thread.
//

import Foundation
import SwiftData
import Observation
import OSLog

private final class CDVMObserverToken {
    private let token: NSObjectProtocol
    init(_ token: NSObjectProtocol) { self.token = token }
    deinit { NotificationCenter.default.removeObserver(token) }
}

@Observable
@MainActor
final class ClientDetailViewModel {

    // MARK: - Inputs
    let client: Client
    private let modelContext: ModelContext
    private let visitRepository: VisitRepositoryProtocol
    private let eventBus: GlobalEventBus

    // MARK: - Outputs
    var pets: [Pet] = []
    var recentVisits: [Visit] = []
    /// Maps a pet's persistent ID → its currently-open visit's persistent ID.
    ///
    /// Sourced from a fresh store query (`endedAt == nil`) rather than the
    /// in-memory `pet.visits` relationship. After `CheckoutTransactionActor`
    /// commits on its own `ModelContext`, the main context's materialized
    /// `Visit.endedAt` can stay stale, leaving `pet.activeVisit` reporting a
    /// session that has already ended (the lingering "In Session" badge). A
    /// predicate fetch filters at the store layer against the actor's committed
    /// write, so a checked-out visit is correctly excluded.
    private(set) var activeVisitIDByPetID: [PersistentIdentifier: PersistentIdentifier] = [:]
    var historyRange: HistoryRange = .all { didSet { refreshRecentVisits() } }
    private(set) var canLoadMore: Bool = false
    var appError: AppError? = nil

    // Derived stats
    var visitCount: Int  { recentVisits.count }
    var grandRevenue: Decimal { recentVisits.reduce(0) { $0 + $1.effectiveTotal } }

    // MARK: - Private paging state
    private let pageSize: Int = 50
    private var currentLimit: Int
    private var lastTotalForClient: Int = 0
    private var fetchTask: Task<Void, Never>?
    private var visitCompleteObserver: CDVMObserverToken?
    private var checkingInPetIDs: Set<PersistentIdentifier> = []

    init(
        client: Client,
        modelContext: ModelContext,
        initialLimit: Int = 50,
        eventBus: GlobalEventBus = GlobalEventBus()
    ) {
        self.client        = client
        self.modelContext  = modelContext
        self.eventBus      = eventBus
        self.visitRepository = VisitRepository(modelContext: modelContext, eventBus: eventBus)
        self.pets          = client.pets ?? []
        self.currentLimit  = max(1, initialLimit)
        let clientID = client.persistentModelID
        let token = NotificationCenter.default.addObserver(
            forName: .visitDidComplete, object: nil, queue: .main
        ) { [weak self] notif in
            // The block runs on the main queue, but it's a `(Notification) -> Void`
            // closure that the compiler treats as nonisolated. Hop to MainActor
            // explicitly so calling `refreshPets()` / `refreshRecentVisits()` is
            // safe under Swift 6 strict-concurrency.
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Only refresh if the completed visit belongs to one of this client's pets.
                // Fall back to refreshing if we can't tell, so we never show stale state.
                if let visitClientID = notif.clientID, visitClientID != clientID { return }
                if let completedPetID = notif.petID {
                    self.activeVisitIDByPetID.removeValue(forKey: completedPetID)
                }
                self.refreshPets()
                self.refreshRecentVisits()
            }
        }
        self.visitCompleteObserver = CDVMObserverToken(token)
        refreshActiveVisits()
        refreshRecentVisits()
    }

    // MARK: - Queries

    func activeVisit(for pet: Pet) -> Visit? {
        let petID = pet.persistentModelID
        guard let visitID = activeVisitIDByPetID[petID] else { return nil }
        guard isVisitStillOpenInStore(visitID: visitID, petID: petID) else {
            activeVisitIDByPetID.removeValue(forKey: petID)
            return nil
        }
        return modelContext.model(for: visitID) as? Visit
    }

    func isCheckingIn(_ pet: Pet) -> Bool {
        checkingInPetIDs.contains(pet.persistentModelID)
    }

    func refreshPets() {
        pets = client.pets ?? []
        refreshActiveVisits()
    }

    /// Re-derive which of this client's pets have an open visit by querying the
    /// store directly. Runs on the main actor (the result set is tiny — only
    /// in-progress visits) so the UI sees fresh state synchronously after a
    /// check-in/out or a `.visitDidComplete` event.
    func refreshActiveVisits() {
        let petIDs = Set((client.pets ?? []).map { $0.persistentModelID })
        guard !petIDs.isEmpty else {
            if !activeVisitIDByPetID.isEmpty { activeVisitIDByPetID = [:] }
            return
        }

        var map: [PersistentIdentifier: PersistentIdentifier] = [:]
        let freshContext = ModelContext(modelContext.container)
        let descriptor = FetchDescriptor<Visit>(predicate: #Predicate<Visit> { $0.endedAt == nil })
        if let openVisits = try? freshContext.fetch(descriptor) {
            for visit in openVisits {
                guard let petID = visit.pet?.persistentModelID, petIDs.contains(petID) else { continue }
                map[petID] = visit.persistentModelID
            }
        }
        activeVisitIDByPetID = map
    }

    private func isVisitStillOpenInStore(visitID: PersistentIdentifier, petID: PersistentIdentifier) -> Bool {
        let freshContext = ModelContext(modelContext.container)
        guard let visit = freshContext.model(for: visitID) as? Visit else { return false }
        return visit.endedAt == nil && visit.pet?.persistentModelID == petID
    }

    // Non-async entry-point — creates an internal Task for background work.
    func refreshRecentVisits(limit: Int? = nil) {
        if let limit { currentLimit = max(1, limit) }
        fetchTask?.cancel()
        fetchTask = Task { [weak self] in
            await self?.fetchVisitsAsync()
        }
    }

    func loadMore() {
        currentLimit += pageSize
        fetchTask?.cancel()
        fetchTask = Task { [weak self] in
            await self?.fetchVisitsAsync()
        }
    }

    // MARK: - Background fetch

    private func fetchVisitsAsync() async {
        guard !Task.isCancelled else { return }

        let petIDs     = Set((client.pets ?? []).map { $0.persistentModelID })
        let startBound = computeStartBound()
        let fetchLimit = currentLimit
        let container  = modelContext.container

        #if DEBUG
        let t0 = Date()
        #endif

        do {
            // Filter in background context — returns PersistentIdentifiers in sorted order.
            let filteredIDs: [PersistentIdentifier] = try await Task.detached(priority: .userInitiated) {
                let bgCtx = ModelContext(container)
                let descriptor = FetchDescriptor<Visit>(
                    predicate: #Predicate<Visit> { $0.endedAt != nil },
                    sortBy: [SortDescriptor(\.endedAt, order: .reverse)]
                )
                let results = try bgCtx.fetch(descriptor)
                return results.compactMap { v -> PersistentIdentifier? in
                    guard let pet = v.pet,
                          petIDs.contains(pet.persistentModelID),
                          let endedAt = v.endedAt else { return nil }
                    if let start = startBound, endedAt < start { return nil }
                    return v.persistentModelID
                }
            }.value

            guard !Task.isCancelled else { return }

            // Resolve IDs back to main-context objects.
            let pagedIDs = Array(filteredIDs.prefix(fetchLimit))
            let visits   = pagedIDs.compactMap { modelContext.model(for: $0) as? Visit }

            self.lastTotalForClient = filteredIDs.count
            self.canLoadMore        = filteredIDs.count > fetchLimit
            self.recentVisits       = visits

            #if DEBUG
            let dt = Date().timeIntervalSince(t0)
            Logger.clientDetail.debug("Fetched client visits (bg): total=\(filteredIDs.count), limit=\(fetchLimit) in \(String(format: "%.2f", dt))s")
            #endif
        } catch {
            guard !Task.isCancelled else { return }
            appError = .database(error.localizedDescription)
            Logger.clientDetail.error("Failed to fetch recent visits: \(String(describing: error))")
            recentVisits = []
            canLoadMore  = false
        }
    }

    private func computeStartBound() -> Date? {
        switch historyRange {
        case .all:
            return nil
        case .lastNDays(let days):
            let cal = Calendar.current
            return cal.date(byAdding: .day, value: -days, to: cal.startOfDay(for: Date()))
        }
    }

    // MARK: - Types
    enum HistoryRange: Hashable {
        case all
        case lastNDays(Int)
    }

    // MARK: - Actions

    func recordAttentionOutreach(method: String) {
        let petsToClear = (client.pets ?? []).filter { $0.needsAttention }
        guard !petsToClear.isEmpty else { return }

        do {
            for pet in petsToClear {
                pet.recordAttentionOutreach()
            }

            try modelContext.save()
            refreshPets()

            CloudKitMonitor.shared.recordLocalChange(
                "Recorded \(method) outreach",
                entityName: "Pet",
                recordUUID: petsToClear.first?.uuid,
                changedKeys: ["lastAttentionOutreachAt"]
            )
            NotificationCenter.default.post(name: .serviceDidUpdate, object: nil)
            eventBus.publish(.refreshRequired)
            Logger.clientDetail.info("Cleared needs-attention flag for \(petsToClear.count, privacy: .public) pet(s) after \(method, privacy: .public)")
        } catch {
            appError = .database(error.localizedDescription)
            CloudKitMonitor.shared.reportLocalSaveError(error, operation: "recording attention outreach")
            Logger.clientDetail.error("Failed to record attention outreach: \(String(describing: error))")
        }
    }

    func checkIn(pet: Pet, at date: Date = .now) {
        let petID = pet.persistentModelID
        if activeVisit(for: pet) != nil || checkingInPetIDs.contains(petID) { return }
        checkingInPetIDs.insert(petID)
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.checkingInPetIDs.remove(petID) }
            do {
                _ = try await self.visitRepository.checkIn(pet: pet, date: date)
                self.refreshPets()
                self.refreshRecentVisits()
            } catch {
                self.appError = .database(error.localizedDescription)
                CloudKitMonitor.shared.reportLocalSaveError(error, operation: "checking in pet")
                Logger.clientDetail.error("Failed to check in: \(String(describing: error))")
            }
        }
    }

    func addService(_ service: Service, to visit: Visit, quantity: Int = 1) {
        visit.addItem(title: service.name, unitPrice: service.effectiveBasePrice, quantity: quantity, service: service)
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.visitRepository.saveVisit(visit)
            } catch {
                self.appError = .database(error.localizedDescription)
                CloudKitMonitor.shared.reportLocalSaveError(error, operation: "saving visit service")
                Logger.clientDetail.error("Failed to add service: \(String(describing: error))")
            }
            self.refreshRecentVisits()
        }
    }

    func checkOut(pet: Pet, customTotal: Decimal? = nil, at date: Date = .now) {
        guard let visit = activeVisit(for: pet) else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.visitRepository.checkOut(visit: visit, total: customTotal, now: date)
                self.refreshPets()
                self.refreshRecentVisits()
            } catch {
                self.appError = .database(error.localizedDescription)
                CloudKitMonitor.shared.reportLocalSaveError(error, operation: "checking out pet")
                Logger.clientDetail.error("Failed to check out: \(String(describing: error))")
            }
        }
    }

    @available(*, deprecated, message: "Freezing now occurs centrally when entering Checkout.")
    func pauseVisitForCheckout(pet: Pet, at date: Date = .now) { }
}

private extension Logger {
    static let clientDetail = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "ClientDetail")
}
