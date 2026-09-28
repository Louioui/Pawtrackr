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
        let keywords: [String]
    }
    private struct PendingPetPayload {
        let title: String
        let description: String
        let keywords: [String]
        let relatedClientID: UUID?
        let thumbnailData: Data?
    }
    private var pendingClients: [UUID: PendingClientPayload] = [:]
    private var pendingPets: [UUID: PendingPetPayload] = [:]
    private var flushScheduled = false
    private let debounceInterval: DispatchTimeInterval = .milliseconds(500)

    private init() {}

    /// Returns the Spotlight identifiers that become stale when a client and its cascaded pets are deleted.
    static func searchableIdentifiersForDeletedClient(clientID: UUID, petIDs: [UUID]) -> [String] {
        ["client-\(clientID.uuidString)"] + petIDs.map { "pet-\($0.uuidString)" }
    }

    /// Coalesces rapid Client edits into a single Spotlight write per id.
    nonisolated func scheduleClientIndex(id: UUID, title: String, description: String, keywords: [String] = []) {
        queue.async { [weak self] in
            guard let self else { return }
            self.pendingClients[id] = PendingClientPayload(title: title, description: description, keywords: keywords)
            self.scheduleFlushLocked()
        }
    }

    /// Coalesces rapid Pet edits into a single Spotlight write per id.
    nonisolated func schedulePetIndex(id: UUID, title: String, description: String, keywords: [String] = [], relatedClientID: UUID? = nil, thumbnailData: Data?) {
        queue.async { [weak self] in
            guard let self else { return }
            self.pendingPets[id] = PendingPetPayload(title: title, description: description, keywords: keywords, relatedClientID: relatedClientID, thumbnailData: thumbnailData)
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
            attr.keywords = Self.uniqueKeywords(["client", "customer", "owner", payload.title] + payload.keywords)
            attr.relatedUniqueIdentifier = "client-\(id.uuidString)"
            attr.contentURL = URL(string: "pawtrackr://client/\(id.uuidString)")
            items.append(CSSearchableItem(uniqueIdentifier: "client-\(id.uuidString)", domainIdentifier: "com.pawtrackr.clients", attributeSet: attr))
        }
        for (id, payload) in pets {
            let attr = CSSearchableItemAttributeSet(itemContentType: UTType.item.identifier)
            attr.title = payload.title
            attr.contentDescription = payload.description
            attr.keywords = Self.uniqueKeywords(["pet", "grooming", "animal", payload.title] + payload.keywords)
            attr.relatedUniqueIdentifier = payload.relatedClientID.map { "client-\($0.uuidString)" } ?? "pet-\(id.uuidString)"
            attr.contentURL = URL(string: "pawtrackr://pet/\(id.uuidString)")
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

    nonisolated func indexPet(id: UUID, title: String, description: String, keywords: [String] = [], relatedClientID: UUID? = nil, thumbnailData: Data?) {
        let identifier = "pet-\(id.uuidString)"
        let domain = "com.pawtrackr.pets"
        queue.async { [log] in
            let attributeSet = CSSearchableItemAttributeSet(itemContentType: UTType.item.identifier)
            attributeSet.title = title
            attributeSet.contentDescription = description
            attributeSet.keywords = Self.uniqueKeywords(["pet", "grooming", "animal", title] + keywords)
            attributeSet.relatedUniqueIdentifier = relatedClientID.map { "client-\($0.uuidString)" } ?? identifier
            attributeSet.contentURL = URL(string: "pawtrackr://pet/\(id.uuidString)")
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
            keywords: Self.petKeywords(pet),
            relatedClientID: pet.owner?.uuid,
            thumbnailData: pet.thumbnailData ?? pet.photoData
        )
    }

    nonisolated func indexClient(id: UUID, title: String, description: String, keywords: [String] = []) {
        let identifier = "client-\(id.uuidString)"
        let domain = "com.pawtrackr.clients"
        queue.async { [log] in
            let attributeSet = CSSearchableItemAttributeSet(itemContentType: UTType.item.identifier)
            attributeSet.title = title
            attributeSet.contentDescription = description
            attributeSet.keywords = Self.uniqueKeywords(["client", "customer", "owner", title] + keywords)
            attributeSet.relatedUniqueIdentifier = identifier
            attributeSet.contentURL = URL(string: "pawtrackr://client/\(id.uuidString)")
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
            description: "Client with \((client.pets ?? []).count) pets • Phone: \(client.phone ?? "N/A")",
            keywords: Self.clientKeywords(client)
        )
    }

    nonisolated func removeFromIndex(id: String) {
        queue.async {
            CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [id], completionHandler: nil)
        }
    }

    /// Removes a deleted client and its cascaded pets from Spotlight, including pending debounced updates.
    nonisolated func removeClientAndPetsFromIndex(clientID: UUID, petIDs: [UUID]) {
        let identifiers = Self.searchableIdentifiersForDeletedClient(clientID: clientID, petIDs: petIDs)
        queue.async { [weak self] in
            guard let self else { return }
            self.pendingClients.removeValue(forKey: clientID)
            for petID in petIDs {
                self.pendingPets.removeValue(forKey: petID)
            }
            CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: identifiers) { error in
                if let error {
                    self.log.error("Spotlight delete failed for \(identifiers.count, privacy: .public) item(s): \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }
    
    nonisolated func reindexAll() {
        queue.async {
            CSSearchableIndex.default().deleteAllSearchableItems { error in
                if let error = error {
                    self.log.error("Failed to clear Spotlight index: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    nonisolated func reindexAll(modelContainer: ModelContainer, batchSize: Int = 200) {
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            await self.reindexAllDetached(modelContainer: modelContainer, batchSize: batchSize)
        }
    }

    private func reindexAllDetached(modelContainer: ModelContainer, batchSize: Int) async {
        CSSearchableIndex.default().deleteAllSearchableItems { [log] error in
            if let error {
                log.error("Failed to clear Spotlight index: \(error.localizedDescription, privacy: .public)")
            }
        }

        let context = ModelContext(modelContainer)
        var offset = 0
        while true {
            do {
                var descriptor = FetchDescriptor<Client>(
                    sortBy: [SortDescriptor(\.lastName), SortDescriptor(\.firstName)]
                )
                descriptor.fetchLimit = batchSize
                descriptor.fetchOffset = offset
                descriptor.relationshipKeyPathsForPrefetching = [\Client.pets]
                let clients = try context.fetch(descriptor)
                guard !clients.isEmpty else { break }
                for client in clients {
                    let pets = client.pets ?? []
                    scheduleClientIndex(
                        id: client.uuid,
                        title: client.fullName,
                        description: "Client with \(pets.count) pets • Phone: \(client.phone ?? "N/A")",
                        keywords: Self.clientKeywords(client)
                    )
                    for pet in pets {
                        schedulePetIndex(
                            id: pet.uuid,
                            title: pet.name,
                            description: "\(pet.shortDescriptor) • Owner: \(client.fullName)",
                            keywords: Self.petKeywords(pet),
                            relatedClientID: client.uuid,
                            thumbnailData: pet.thumbnailData ?? pet.photoData
                        )
                    }
                }
                offset += clients.count
                if clients.count < batchSize { break }
            } catch {
                log.error("Spotlight full reindex failed at offset \(offset, privacy: .public): \(error.localizedDescription, privacy: .public)")
                break
            }
        }
    }

    private static func clientKeywords(_ client: Client) -> [String] {
        var keywords = [client.firstName, client.lastName, client.fullName]
        if let phone = client.phone {
            keywords.append(contentsOf: phoneSearchTokens(for: phone))
        }
        if let email = client.email { keywords.append(email) }
        keywords.append(contentsOf: (client.pets ?? []).map(\.name))
        return uniqueKeywords(keywords)
    }

    private static func petKeywords(_ pet: Pet) -> [String] {
        uniqueKeywords([
            pet.name,
            pet.owner?.fullName,
            pet.species.rawValue,
            pet.gender.displayName,
            pet.breed,
            pet.color
        ].compactMap { $0 })
    }

    private static func phoneSearchTokens(for value: String) -> [String] {
        var tokens = [value]
        if let e164 = PhoneUtils.toE164(value) { tokens.append(e164) }
        if let display = PhoneUtils.display(value) { tokens.append(display) }
        let digits = PhoneUtils.normalize(value)
        if !digits.isEmpty {
            tokens.append(digits)
            if digits.count == 11, digits.first == "1" {
                tokens.append(String(digits.dropFirst()))
            }
        }
        return tokens
    }

    private static func uniqueKeywords(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0.lowercased()).inserted }
    }
}
