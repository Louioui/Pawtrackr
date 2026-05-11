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
        
        // Smart Merge Logic: Append notes if both have content
        let mergedNotes = smartMerge(local: localVisit.note, remote: remoteData.note)
        localVisit.note = mergedNotes
        
        // Set merge for behavior tags
        let localTags = Set(localVisit.behaviorTags)
        let remoteTags = Set(remoteData.behaviorTags)
        localVisit.behaviorTags = Array(localTags.union(remoteTags)).sorted()
        
        try modelContext.save()
        syncLog.info("Resolved visit conflict for \(localVisit.uuid)")
    }
    
    private func smartMerge(local: String?, remote: String?) -> String? {
        guard let local = local, !local.isEmpty else { return remote }
        guard let remote = remote, !remote.isEmpty else { return local }
        if local == remote { return local }
        
        return "\(local)\n---\n[Remote Edit]: \(remote)"
    }
    
    struct VisitData: Sendable {
        let note: String?
        let behaviorTags: [String]
    }
}
