import Foundation
import CoreSpotlight
import UniformTypeIdentifiers
import OSLog
import SwiftData

/// Spotlight indexing happens on a dedicated background queue. CSSearchableIndex is
/// thread-safe and its work runs in its own queue, but we still keep the call sites
/// off the main thread so save-path ripple effects don't add latency to UI.
final class SpotlightIndexer: @unchecked Sendable {
    static let shared = SpotlightIndexer()

    private let queue = DispatchQueue(label: "com.pawtrackr.spotlight-indexer", qos: .utility)
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "Spotlight")

    /// Per-id coalescing buffer for client/pet updates. A 4-tap edit on a Client
    /// (firstName, lastName, phone, email) used to trigger 4 re-indexes; this
    /// collapses them into one batch flushed after `debounceInterval`.
    private struct PendingClientPayload {
        let title: String
        let description: String
    }
    private struct PendingPetPayload {
        let title: String
        let description: String
        let thumbnailData: Data?
    }
    private var pendingClients: [UUID: PendingClientPayload] = [:]
    private var pendingPets: [UUID: PendingPetPayload] = [:]
    private var flushScheduled = false
    private let debounceInterval: DispatchTimeInterval = .milliseconds(500)

    private init() {}

    /// Coalesces rapid Client edits into a single Spotlight write per id.
    nonisolated func scheduleClientIndex(id: UUID, title: String, description: String) {
        queue.async { [weak self] in
            guard let self else { return }
            self.pendingClients[id] = PendingClientPayload(title: title, description: description)
            self.scheduleFlushLocked()
        }
    }

    /// Coalesces rapid Pet edits into a single Spotlight write per id.
    nonisolated func schedulePetIndex(id: UUID, title: String, description: String, thumbnailData: Data?) {
        queue.async { [weak self] in
            guard let self else { return }
            self.pendingPets[id] = PendingPetPayload(title: title, description: description, thumbnailData: thumbnailData)
            self.scheduleFlushLocked()
        }
    }

    /// Caller already on `queue`.
    private func scheduleFlushLocked() {
        guard !flushScheduled else { return }
        flushScheduled = true
        queue.asyncAfter(deadline: .now() + debounceInterval) { [weak self] in
            self?.flushPending()
        }
    }

    /// Caller already on `queue`.
    private func flushPending() {
        let clients = pendingClients
        let pets = pendingPets
        pendingClients.removeAll(keepingCapacity: true)
        pendingPets.removeAll(keepingCapacity: true)
        flushScheduled = false

        var items: [CSSearchableItem] = []
        items.reserveCapacity(clients.count + pets.count)

        for (id, payload) in clients {
            let attr = CSSearchableItemAttributeSet(itemContentType: UTType.item.identifier)
            attr.title = payload.title
            attr.contentDescription = payload.description
            attr.keywords = ["client", "customer", "owner", payload.title]
            items.append(CSSearchableItem(uniqueIdentifier: "client-\(id.uuidString)", domainIdentifier: "com.pawtrackr.clients", attributeSet: attr))
        }
        for (id, payload) in pets {
            let attr = CSSearchableItemAttributeSet(itemContentType: UTType.item.identifier)
            attr.title = payload.title
            attr.contentDescription = payload.description
            attr.keywords = ["pet", "grooming", "animal", payload.title]
            if let data = payload.thumbnailData { attr.thumbnailData = data }
            items.append(CSSearchableItem(uniqueIdentifier: "pet-\(id.uuidString)", domainIdentifier: "com.pawtrackr.pets", attributeSet: attr))
        }

        guard !items.isEmpty else { return }
        let log = self.log
        CSSearchableIndex.default().indexSearchableItems(items) { error in
            if let error = error {
                log.error("Spotlight batch index failed for \(items.count) items: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    nonisolated func indexPet(id: UUID, title: String, description: String, thumbnailData: Data?) {
        let identifier = "pet-\(id.uuidString)"
        let domain = "com.pawtrackr.pets"
        queue.async { [log] in
            let attributeSet = CSSearchableItemAttributeSet(itemContentType: UTType.item.identifier)
            attributeSet.title = title
            attributeSet.contentDescription = description
            attributeSet.keywords = ["pet", "grooming", "animal", title]
            if let data = thumbnailData {
                attributeSet.thumbnailData = data
            }
            let item = CSSearchableItem(uniqueIdentifier: identifier, domainIdentifier: domain, attributeSet: attributeSet)
            CSSearchableIndex.default().indexSearchableItems([item]) { error in
                if let error = error {
                    log.error("Error indexing pet: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    @MainActor
    func indexPet(_ pet: Pet) {
        indexPet(
            id: pet.uuid,
            title: pet.name,
            description: "\(pet.shortDescriptor) • Owner: \(pet.owner?.fullName ?? "Unknown")",
            thumbnailData: pet.thumbnailData ?? pet.photoData
        )
    }

    nonisolated func indexClient(id: UUID, title: String, description: String) {
        let identifier = "client-\(id.uuidString)"
        let domain = "com.pawtrackr.clients"
        queue.async { [log] in
            let attributeSet = CSSearchableItemAttributeSet(itemContentType: UTType.item.identifier)
            attributeSet.title = title
            attributeSet.contentDescription = description
            attributeSet.keywords = ["client", "customer", "owner", title]
            let item = CSSearchableItem(uniqueIdentifier: identifier, domainIdentifier: domain, attributeSet: attributeSet)
            CSSearchableIndex.default().indexSearchableItems([item]) { error in
                if let error = error {
                    log.error("Error indexing client: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    @MainActor
    func indexClient(_ client: Client) {
        indexClient(
            id: client.uuid,
            title: client.fullName,
            description: "Client with \((client.pets ?? []).count) pets • Phone: \(client.phone ?? "N/A")"
        )
    }

    nonisolated func removeFromIndex(id: String) {
        queue.async {
            CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [id], completionHandler: nil)
        }
    }
    
    nonisolated func reindexAll() {
        queue.async {
            CSSearchableIndex.default().deleteAllSearchableItems { error in
                if let error = error {
                    self.log.error("Failed to clear Spotlight index: \(error.localizedDescription, privacy: .public)")
                }
            }
            // In a real app, you would then iterate and re-index all records here.
        }
    }
}
