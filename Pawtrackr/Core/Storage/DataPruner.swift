//
//  DataPruner.swift
//  Pawtrackr
//
//  Utility to manage app storage by pruning or downsampling old data.
//

import Foundation
import SwiftData
import OSLog

enum DataPruner {
    /// Prunes or downsamples photos older than the specified age.
    /// - Parameters:
    ///   - days: Age in days beyond which photos should be pruned.
    ///   - downsampleOnly: If true, high-res photos are downsampled to thumbnails instead of being deleted.
    ///   - context: The ModelContext to use for operations.
    static func pruneOldPhotos(
        olderThan days: Int,
        downsampleOnly: Bool = true,
        pruneSyncedAssets: Bool = false,
        in context: ModelContext
    ) {
        guard pruneSyncedAssets else {
            Logger.maintenance.info("Skipping photo pruning: visit photos are CloudKit-synced user data, not a local cache.")
            return
        }

        let cal = Calendar.current
        guard let cutoffDate = cal.date(byAdding: .day, value: -days, to: .now) else { return }
        
        Logger.maintenance.info("Starting photo pruning for items older than \(days) days (Downsample only: \(downsampleOnly))")
        
        // Batch the work so a long-lived store with thousands of old visits
        // doesn't hold every match in memory + a single save at the end.
        let batchSize = 100
        var offset = 0
        var processedCount = 0

        do {
            while true {
                var descriptor = FetchDescriptor<Visit>(
                    predicate: #Predicate<Visit> { $0.startedAt < cutoffDate },
                    sortBy: [SortDescriptor(\.startedAt, order: .forward)]
                )
                descriptor.fetchOffset = offset
                descriptor.fetchLimit = batchSize

                let batch = try context.fetch(descriptor)
                if batch.isEmpty { break }

                var batchChanged = false
                for visit in batch {
                    var changed = false

                    // Process Before Photo
                    if let beforeData = visit.beforePhotoData {
                        if downsampleOnly {
                            if visit.beforeThumbnailData == nil {
                                visit.beforeThumbnailData = ImageCache.shared.downsampleToData(data: beforeData, maxDimension: 200)
                            }
                            visit.beforePhotoData = nil
                        } else {
                            visit.beforePhotoData = nil
                            visit.beforeThumbnailData = nil
                        }
                        changed = true
                    }

                    // Process After Photo
                    if let afterData = visit.afterPhotoData {
                        if downsampleOnly {
                            if visit.afterThumbnailData == nil {
                                visit.afterThumbnailData = ImageCache.shared.downsampleToData(data: afterData, maxDimension: 200)
                            }
                            visit.afterPhotoData = nil
                        } else {
                            visit.afterPhotoData = nil
                            visit.afterThumbnailData = nil
                        }
                        changed = true
                    }

                    if changed {
                        processedCount += 1
                        batchChanged = true
                    }
                }

                if batchChanged {
                    try context.save()
                }
                offset += batch.count

                // If the batch was short, we're done.
                if batch.count < batchSize { break }
            }
            Logger.maintenance.info("Pruning complete. Processed \(processedCount) visits.")
        } catch {
            Logger.maintenance.error("Pruning failed at offset \(offset): \(error.localizedDescription)")
        }
    }
}

private extension Logger {
    static let maintenance = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "maintenance")
}
