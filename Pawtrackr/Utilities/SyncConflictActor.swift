//
//  SyncConflictActor.swift
//  Pawtrackr
//
//  Specialized actor for managing and resolving data conflicts in multi-device sync.
//  Implements "Smart Merge" logic for text fields and priority-based resolution.
//

import Foundation
import SwiftData
import OSLog

private let syncLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "SyncConflict")

@ModelActor
final actor SyncConflictActor {
    
    func resolveVisitConflict(localID: PersistentIdentifier, remoteData: VisitData) async throws {
        guard let localVisit = modelContext.model(for: localID) as? Visit else { return }
        
        var didChange = false

        // Smart Merge Logic: append notes only when the remote edit is new.
        let mergedNotes = smartMerge(local: localVisit.note, remote: remoteData.note)
        if localVisit.note != mergedNotes {
            localVisit.note = mergedNotes
            didChange = true
        }
        
        // Field-wise set merge for behavior tags, with deterministic ordering.
        let mergedTags = mergedTags(local: localVisit.behaviorTags, remote: remoteData.behaviorTags)
        if localVisit.behaviorTags != mergedTags {
            localVisit.behaviorTags = mergedTags
            didChange = true
        }

        guard didChange else {
            syncLog.debug("Skipped no-op visit conflict resolution for \(localVisit.uuid)")
            return
        }

        let now = Date()
        localVisit.updatedAt = now
        localVisit.lastModifiedAt = now
        localVisit.lastModifiedBy = DeviceIdentity.currentID
        
        try modelContext.save()
        syncLog.info("Resolved visit conflict for \(localVisit.uuid)")
    }
    
    private func smartMerge(local: String?, remote: String?) -> String? {
        guard let local = normalizedText(local) else { return normalizedText(remote) }
        guard let remote = normalizedText(remote) else { return local }
        if local == remote { return local }
        if local.contains(remote) { return local }
        
        return "\(local)\n---\n[Remote Edit]: \(remote)"
    }

    private func normalizedText(_ value: String?) -> String? {
        guard let cleaned = value?.trimmingCharacters(in: .whitespacesAndNewlines), !cleaned.isEmpty else {
            return nil
        }
        return cleaned
    }

    private func mergedTags(local: [String], remote: [String]) -> [String] {
        Set((local + remote).compactMap(normalizedText(_:)))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
    
    struct VisitData: Sendable {
        let note: String?
        let behaviorTags: [String]
    }
}
