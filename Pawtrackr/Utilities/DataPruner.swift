
//
//  DataPruner.swift
//  Pawtrackr
//
//  Created by Gemini on 9/15/25.
//

import Foundation
import SwiftData

@ModelActor
actor DataPruner {
    /// Hard-delete entire Visit objects started before a cutoff date.
    func pruneVisits(olderThan date: Date) throws {
        let predicate = #Predicate<Visit> { visit in visit.startedAt < date }
        try modelContext.delete(model: Visit.self, where: predicate)
        try modelContext.save()
    }

    /// Drops large media blobs from older visits while keeping the Visit rows for analytics.
    /// - Parameters:
    ///   - olderThan: Only visits with `endedAt` before this date are considered.
    ///   - keepRecentPhotosPerPet: Always keep photos for the most recent N visits per pet.
    func pruneVisitPhotos(olderThan cutoff: Date, keepRecentPhotosPerPet: Int = 2) throws {
        // 1) Fetch candidate visits (completed and before cutoff)
        let predicate = #Predicate<Visit> { v in
            if let endedAt = v.endedAt {
                return endedAt < cutoff
            } else {
                return false
            }
        }
        let desc = FetchDescriptor<Visit>(predicate: predicate, sortBy: [SortDescriptor(\.endedAt, order: .reverse)])
        let visits = (try? modelContext.fetch(desc)) ?? []

        // 2) Track per-pet recent count so we keep the latest N with photos
        var keptPerPet: [PersistentIdentifier: Int] = [:]
        for v in visits {
            guard let petID = v.pet?.persistentModelID else { continue }
            let kept = keptPerPet[petID, default: 0]
            if kept < keepRecentPhotosPerPet && (v.beforePhotoData != nil || v.afterPhotoData != nil) {
                keptPerPet[petID] = kept + 1
                continue // keep photos for this one
            }
            // Remove media blobs to reclaim disk space; keep the rest of the record for history/analytics.
            if v.beforePhotoData != nil || v.afterPhotoData != nil {
                v.beforePhotoData = nil
                v.afterPhotoData = nil
            }
        }
        try modelContext.save()
    }

    /// Compacts derived data by rebuilding day summaries for a date window.
    /// Safe to run periodically (e.g., weekly) alongside event-driven updates.
    func compactSummaries(in range: ClosedRange<Date>) {
        var day = Calendar.current.startOfDay(for: range.lowerBound)
        let end = Calendar.current.startOfDay(for: range.upperBound)
        while day <= end {
            SummaryUpdater.rebuildDay(for: day, in: modelContext)
            guard let next = Calendar.current.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
    }
}
