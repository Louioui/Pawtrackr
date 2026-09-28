import Foundation
import CoreSpotlight
import OSLog
import SwiftData

/// The Spotlight calls SpotlightIndexer makes, so tests can record them
/// instead of writing to the device's index.
protocol SpotlightIndexWriting: AnyObject, Sendable {
    func index(_ items: [CSSearchableItem], completion: @escaping @Sendable (Error?) -> Void)
    func delete(identifiers: [String], completion: @escaping @Sendable (Error?) -> Void)
    func deleteAll(completion: @escaping @Sendable (Error?) -> Void)
}

/// The app's real index.
final class SystemSpotlightIndex: SpotlightIndexWriting, @unchecked Sendable {
    func index(_ items: [CSSearchableItem], completion: @escaping @Sendable (Error?) -> Void) {
        CSSearchableIndex.default().indexSearchableItems(items) { completion($0) }
    }

    func delete(identifiers: [String], completion: @escaping @Sendable (Error?) -> Void) {
        CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: identifiers) { completion($0) }
    }

    func deleteAll(completion: @escaping @Sendable (Error?) -> Void) {
        CSSearchableIndex.default().deleteAllSearchableItems { completion($0) }
    }
}

/// How a full rebuild ended.
enum SpotlightRebuildOutcome: Equatable, Sendable {
    case completed(clients: Int, pets: Int)
    /// The privacy policy doesn't allow indexing (or hasn't been published yet).
    case skippedByPolicy
    /// App Lock came on, Start Fresh ran, or a newer rebuild started.
    case cancelled
    case failed
}

/// Puts clients and pets in Spotlight.
///
/// - Live edits: `Client`/`Pet` setters call `scheduleIndex`, which copies a
///   snapshot on the model's own thread; a per-id buffer coalesces a
///   multi-field edit into one write 500 ms later.
/// - Full rebuild: `reindexAll(container:)` deletes everything, waits for the
///   delete, then re-reads the store from fresh background contexts in
///   batches and indexes each batch directly.
/// - Privacy: nothing is indexed unless `SpotlightPrivacyPolicy` allows it.
///   The policy check and every submit to the index happen under one lock,
///   the same lock the App Lock transition takes to flip the policy and
///   delete everything, so no item can land after that delete.
final class SpotlightIndexer: @unchecked Sendable {
    static let shared = SpotlightIndexer()

    /// UserDefaults key holding the last `SpotlightIndexState`.
    static let indexStateKey = "spotlight.indexState"
    static let defaultBatchSize = 200

    private let index: SpotlightIndexWriting
    private let defaults: UserDefaults
    private let debounceInterval: DispatchTimeInterval
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "Spotlight")

    // Confined to `queue`.
    private let queue = DispatchQueue(label: "com.pawtrackr.spotlight-indexer", qos: .utility)
    private var pendingClients: [UUID: SpotlightClientSnapshot] = [:]
    private var pendingPets: [UUID: SpotlightPetSnapshot] = [:]
    private var flushScheduled = false

    // Guarded by `stateLock`. Never held across an await.
    private let stateLock = NSLock()
    /// nil until AppSettings publishes the policy. Fails closed: nothing is
    /// indexed before the app knows whether the lock is on.
    private var allowsIndexingValue: Bool?
    /// Bumped by every rebuild, privacy removal and Start Fresh, so an older
    /// rebuild stops at its next submit.
    private var generation = 0
    private var container: ModelContainer?

    init(
        index: SpotlightIndexWriting = SystemSpotlightIndex(),
        defaults: UserDefaults = .standard,
        debounceInterval: DispatchTimeInterval = .milliseconds(500)
    ) {
        self.index = index
        self.defaults = defaults
        self.debounceInterval = debounceInterval
    }

    /// Returns the Spotlight identifiers that become stale when a client and its cascaded pets are deleted.
    static func searchableIdentifiersForDeletedClient(clientID: UUID, petIDs: [UUID]) -> [String] {
        [SpotlightIdentifier.client(clientID).rawValue] + petIDs.map { SpotlightIdentifier.pet($0).rawValue }
    }

    // MARK: - Setup

    /// The store a rebuild reads when App Lock is turned off. Set once at launch.
    func attach(container: ModelContainer) {
        stateLock.withLock { self.container = container }
    }

    /// Forces the next launch check to rebuild, e.g. after a store restore
    /// swapped in different records.
    func markIndexStale() {
        stateLock.withLock { writeStateLocked(nil) }
    }

    var isIndexingAllowed: Bool {
        stateLock.withLock { allowsIndexingValue == true }
    }

    var storedIndexState: SpotlightIndexState? {
        stateLock.withLock { readStateLocked() }
    }

    // MARK: - Privacy policy

    /// Called by AppSettings with `SpotlightPrivacyPolicy.allowsIndexing` at
    /// launch and whenever the lock setting or the PIN changes. Repeating the
    /// same value does nothing.
    @discardableResult
    func applyPrivacyPolicy(allowsIndexing: Bool) -> SpotlightIndexAction {
        let (action, container): (SpotlightIndexAction, ModelContainer?) = stateLock.withLock {
            let previous = allowsIndexingValue
            allowsIndexingValue = allowsIndexing
            let action = SpotlightIndexPlan.onPolicyChange(previous: previous, current: allowsIndexing, stored: readStateLocked())
            switch action {
            case .removeAll:
                removeAllForPrivacyLocked()
            case .rebuild:
                // Stale until the rebuild finishes, so a crash midway rebuilds
                // again on the next launch.
                writeStateLocked(nil)
            case .none:
                break
            }
            return (action, self.container)
        }

        switch action {
        case .removeAll:
            // Any flush that runs before this is dropped by the policy check.
            queue.async { [weak self] in self?.clearPendingOnQueue() }
        case .rebuild:
            if let container {
                Task.detached(priority: .utility) { [weak self] in
                    _ = await self?.reindexAll(container: container)
                }
            } else {
                log.info("Spotlight: index allowed again; no store attached yet, so the launch check rebuilds.")
            }
        case .none:
            break
        }
        return action
    }

    /// Runs once per launch after the store is open and the first iCloud
    /// import has settled: clears the index if the lock forbids it, rebuilds
    /// it if it predates the current item format.
    @discardableResult
    func reconcileAtLaunch(container: ModelContainer) async -> SpotlightIndexAction {
        attach(container: container)
        let action: SpotlightIndexAction = stateLock.withLock {
            guard let allowed = allowsIndexingValue else { return .none }
            let action = SpotlightIndexPlan.atLaunch(allowsIndexing: allowed, stored: readStateLocked())
            if action == .removeAll {
                removeAllForPrivacyLocked()
            }
            return action
        }
        switch action {
        case .removeAll:
            queue.async { [weak self] in self?.clearPendingOnQueue() }
        case .rebuild:
            _ = await reindexAll(container: container)
        case .none:
            break
        }
        return action
    }

    /// Caller holds `stateLock`.
    private func removeAllForPrivacyLocked() {
        generation &+= 1
        let log = self.log
        index.deleteAll { error in
            if let error {
                log.error("Spotlight: removing items for App Lock failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        writeStateLocked(.cleared)
    }

    // MARK: - Live edits

    /// Queues a client (and, when its name or phone changed or a pet was
    /// added, its pets, whose items carry the owner's name and phone).
    /// Call on the thread that owns the client's ModelContext.
    func scheduleIndex(client: Client, includingPets: Bool = false) {
        guard isIndexingAllowed else { return }
        let snapshot = SpotlightClientSnapshot(client: client)
        let pets = includingPets ? (client.pets ?? []).map(SpotlightPetSnapshot.init(pet:)) : []
        enqueue(clients: [snapshot], pets: pets)
    }

    /// Queues a pet. Call on the thread that owns the pet's ModelContext.
    func scheduleIndex(pet: Pet) {
        guard isIndexingAllowed else { return }
        enqueue(clients: [], pets: [SpotlightPetSnapshot(pet: pet)])
    }

    private func enqueue(clients: [SpotlightClientSnapshot], pets: [SpotlightPetSnapshot]) {
        queue.async { [weak self] in
            guard let self else { return }
            for client in clients { self.pendingClients[client.id] = client }
            for pet in pets { self.pendingPets[pet.id] = pet }
            self.scheduleFlushOnQueue()
        }
    }

    private func scheduleFlushOnQueue() {
        guard !flushScheduled else { return }
        flushScheduled = true
        queue.asyncAfter(deadline: .now() + debounceInterval) { [weak self] in
            self?.flushPendingOnQueue()
        }
    }

    private func flushPendingOnQueue() {
        let clients = pendingClients
        let pets = pendingPets
        pendingClients.removeAll(keepingCapacity: true)
        pendingPets.removeAll(keepingCapacity: true)
        flushScheduled = false

        let items = clients.values.map { SpotlightContentBuilder.searchableItem(for: SpotlightContentBuilder.clientContent($0)) }
            + pets.values.map { SpotlightContentBuilder.searchableItem(for: SpotlightContentBuilder.petContent($0)) }
        guard !items.isEmpty else { return }
        let count = items.count
        let log = self.log
        _ = submitLocked(items, generation: nil) { error in
            if let error {
                log.error("Spotlight batch index failed for \(count, privacy: .public) items: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func clearPendingOnQueue() {
        pendingClients.removeAll()
        pendingPets.removeAll()
    }

    /// Checks the policy (and, for a rebuild, that it is still the current
    /// one) and submits, all under `stateLock`. Returns false when nothing was
    /// submitted; `completion` then never runs.
    private func submitLocked(_ items: [CSSearchableItem], generation expected: Int?, completion: @escaping @Sendable (Error?) -> Void) -> Bool {
        stateLock.withLock {
            guard allowsIndexingValue == true else { return false }
            if let expected, expected != generation { return false }
            index.index(items, completion: completion)
            return true
        }
    }

    // MARK: - Removal

    /// Removes a deleted client and its cascaded pets from Spotlight, including pending debounced updates.
    func removeClientAndPetsFromIndex(clientID: UUID, petIDs: [UUID]) {
        let identifiers = Self.searchableIdentifiersForDeletedClient(clientID: clientID, petIDs: petIDs)
        queue.async { [weak self] in
            guard let self else { return }
            self.pendingClients.removeValue(forKey: clientID)
            for petID in petIDs {
                self.pendingPets.removeValue(forKey: petID)
            }
            let log = self.log
            self.index.delete(identifiers: identifiers) { error in
                if let error {
                    log.error("Spotlight delete failed for \(identifiers.count, privacy: .public) item(s): \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    /// Removes a deleted pet, including a pending debounced update.
    func removePetFromIndex(petID: UUID) {
        queue.async { [weak self] in
            guard let self else { return }
            self.pendingPets.removeValue(forKey: petID)
            let log = self.log
            self.index.delete(identifiers: [SpotlightIdentifier.pet(petID).rawValue]) { error in
                if let error {
                    log.error("Spotlight pet delete failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    /// Start Fresh: every client is gone, so remove every item and drop
    /// pending edits and any running rebuild. Leaves the stored state alone,
    /// since an empty index is the right index for an empty store.
    func removeAllItems() {
        queue.async { [weak self] in
            guard let self else { return }
            self.clearPendingOnQueue()
            let log = self.log
            self.stateLock.withLock {
                self.generation &+= 1
                self.index.deleteAll { error in
                    if let error {
                        log.error("Failed to clear Spotlight index: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
        }
    }

    // MARK: - Full rebuild

    /// Deletes every Pawtrackr item, waits for that, then indexes every client
    /// and pet in batches of `batchSize`, each read from a fresh background
    /// ModelContext and submitted straight to the index. Stops early if App
    /// Lock comes on, Start Fresh runs or another rebuild starts.
    @discardableResult
    func reindexAll(container: ModelContainer, batchSize: Int = SpotlightIndexer.defaultBatchSize) async -> SpotlightRebuildOutcome {
        let batchSize = max(1, batchSize)
        let started: Int? = stateLock.withLock {
            guard allowsIndexingValue == true else { return nil }
            generation &+= 1
            writeStateLocked(nil)
            return generation
        }
        guard let rebuild = started else { return .skippedByPolicy }

        let log = self.log
        let deleted: Bool = await withCheckedContinuation { continuation in
            let submitted: Bool = stateLock.withLock {
                guard allowsIndexingValue == true, generation == rebuild else { return false }
                index.deleteAll { error in
                    if let error {
                        log.error("Spotlight rebuild: clearing the index failed: \(error.localizedDescription, privacy: .public)")
                    }
                    continuation.resume(returning: true)
                }
                return true
            }
            if !submitted { continuation.resume(returning: false) }
        }
        guard deleted else { return .cancelled }

        let clients = await indexInBatches(
            Client.self,
            sortBy: [SortDescriptor(\Client.createdAt), SortDescriptor(\Client.lastName), SortDescriptor(\Client.firstName)],
            container: container,
            batchSize: batchSize,
            generation: rebuild
        ) { SpotlightContentBuilder.clientContent(SpotlightClientSnapshot(client: $0)) }
        guard case .success(let clientCount) = clients else { return clients.outcome }

        let pets = await indexInBatches(
            Pet.self,
            sortBy: [SortDescriptor(\Pet.createdAt), SortDescriptor(\Pet.name)],
            container: container,
            batchSize: batchSize,
            generation: rebuild
        ) { SpotlightContentBuilder.petContent(SpotlightPetSnapshot(pet: $0)) }
        guard case .success(let petCount) = pets else { return pets.outcome }

        let finished: Bool = stateLock.withLock {
            guard allowsIndexingValue == true, generation == rebuild else { return false }
            writeStateLocked(.built(format: SpotlightIndexPlan.currentFormat))
            return true
        }
        guard finished else { return .cancelled }
        log.info("Spotlight rebuild indexed \(clientCount, privacy: .public) clients and \(petCount, privacy: .public) pets.")
        return .completed(clients: clientCount, pets: petCount)
    }

    private enum BatchResult {
        case success(Int)
        case stopped(SpotlightRebuildOutcome)

        var outcome: SpotlightRebuildOutcome {
            switch self {
            case .success: return .failed
            case .stopped(let outcome): return outcome
            }
        }
    }

    private func indexInBatches<Model: PersistentModel>(
        _ type: Model.Type,
        sortBy: [SortDescriptor<Model>],
        container: ModelContainer,
        batchSize: Int,
        generation rebuild: Int,
        content: (Model) -> SpotlightItemContent
    ) async -> BatchResult {
        var offset = 0
        while true {
            let items: [CSSearchableItem]
            do {
                // A fresh context per batch, so faults and thumbnails from
                // earlier batches are released instead of piling up.
                let context = ModelContext(container)
                var descriptor = FetchDescriptor<Model>(sortBy: sortBy)
                descriptor.fetchOffset = offset
                descriptor.fetchLimit = batchSize
                items = try context.fetch(descriptor).map { SpotlightContentBuilder.searchableItem(for: content($0)) }
            } catch {
                log.error("Spotlight rebuild: fetching \(String(describing: Model.self), privacy: .public) at offset \(offset, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                return .stopped(.failed)
            }
            guard !items.isEmpty else { return .success(offset) }

            let log = self.log
            let submitted: Bool = await withCheckedContinuation { continuation in
                let accepted = submitLocked(items, generation: rebuild) { error in
                    if let error {
                        log.error("Spotlight rebuild: indexing a batch failed: \(error.localizedDescription, privacy: .public)")
                    }
                    continuation.resume(returning: true)
                }
                if !accepted { continuation.resume(returning: false) }
            }
            guard submitted else { return .stopped(.cancelled) }

            offset += items.count
            if items.count < batchSize { return .success(offset) }
        }
    }

    // MARK: - Stored state (caller holds `stateLock`)

    private func readStateLocked() -> SpotlightIndexState? {
        SpotlightIndexState(storedValue: defaults.string(forKey: Self.indexStateKey))
    }

    private func writeStateLocked(_ state: SpotlightIndexState?) {
        if let state {
            defaults.set(state.storedValue, forKey: Self.indexStateKey)
        } else {
            defaults.removeObject(forKey: Self.indexStateKey)
        }
    }
}
