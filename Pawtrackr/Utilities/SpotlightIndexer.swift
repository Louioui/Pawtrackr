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

    private init() {}

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
