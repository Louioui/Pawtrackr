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

    /// Clears auxiliary caches and rebuilds Spotlight index. Does NOT touch the
    /// SwiftData store itself — if that's unhealthy, callers need a full
    /// `DataStoreRecoveryView` flow.
    static func clearAuxiliaryCaches() {
        log.info("Clearing auxiliary caches and re-indexing Spotlight…")
        ImageCache.shared.clearCache()
        SpotlightIndexer.shared.reindexAll()
        log.info("Auxiliary caches cleared.")
    }

    @available(*, deprecated, renamed: "clearAuxiliaryCaches", message: "This never repaired the SwiftData store; only cleared image cache and Spotlight.")
    static func repairStore() {
        clearAuxiliaryCaches()
    }
}
