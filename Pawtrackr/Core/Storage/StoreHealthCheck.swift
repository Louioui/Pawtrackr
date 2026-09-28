//
//  StoreHealthCheck.swift
//  Pawtrackr
//
//  Utility to perform basic sanity checks on the SwiftData ModelContainer.
//

import Foundation
import SwiftData
import OSLog

struct StoreHealthCheck {
    private static let log = Logger(subsystem: "com.pawtrackr", category: "DataIntegrity")
    
    /// Performs a light-weight check on the store.
    /// Returns true if the store is healthy, false otherwise.
    static func isStoreHealthy(container: ModelContainer) -> Bool {
        let context = ModelContext(container)
        do {
            // Attempt a simple fetch to ensure the store is accessible.
            let descriptor = FetchDescriptor<BusinessConfig>()
            _ = try context.fetch(descriptor)
            return true
        } catch {
            log.error("Store integrity check failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Clears the image cache and rebuilds the Spotlight index from the
    /// store, off the main actor. Only reads the SwiftData store; if that's
    /// unhealthy, callers need a full `DataStoreRecoveryView` flow. The
    /// rebuild honours `SpotlightPrivacyPolicy`, so with App Lock on it
    /// indexes nothing. Returns the rebuild task so callers can await it.
    @discardableResult
    static func clearAuxiliaryCaches(
        container: ModelContainer,
        spotlight: SpotlightIndexer = .shared
    ) -> Task<SpotlightRebuildOutcome, Never> {
        log.info("Clearing auxiliary caches and rebuilding Spotlight…")
        ImageCache.shared.clearCache()
        return Task.detached(priority: .utility) {
            let outcome = await spotlight.reindexAll(container: container)
            log.info("Auxiliary caches cleared; Spotlight rebuild: \(String(describing: outcome), privacy: .public)")
            return outcome
        }
    }
}
