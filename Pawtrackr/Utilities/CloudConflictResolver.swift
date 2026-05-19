//
//  CloudConflictResolver.swift
//  Pawtrackr
//
//  Logic to resolve concurrent edits on the same model.
//  Prefers newer updates based on 'updatedAt' but allows for smart merging.
//

import Foundation
import SwiftData

enum CloudConflictResolver {
    
    /// Compares a local model with a remote one and returns the 'winner' 
    /// or a merged version if possible.
    static func resolve<T: PersistentModel & ConflictResolvable>(local: T, remote: T) {
        // If the remote version is newer, apply its changes to the local version
        if remote.updatedAt > local.updatedAt {
            local.resolveConflict(with: remote)
        }
    }
}

protocol ConflictResolvable {
    var updatedAt: Date { get }
    func resolveConflict(with other: Self)
}

extension Client: ConflictResolvable {
    func resolveConflict(with other: Client) {
        // Only update fields that are actually different and newer
        if other.firstName != firstName { firstName = other.firstName }
        if other.lastName != lastName { lastName = other.lastName }
        if other.phone != phone { phone = other.phone }
        if other.email != email { email = other.email }
        if other.address != address { address = other.address }
        if other.notes != notes { notes = other.notes }
        if other.photoData != nil { photoData = other.photoData }
        if other.thumbnailData != nil { thumbnailData = other.thumbnailData }
        updatedAt = other.updatedAt
        lastModifiedBy = other.lastModifiedBy
    }
}

extension Pet: ConflictResolvable {
    func resolveConflict(with other: Pet) {
        if other.name != name { name = other.name }
        if other.species != species { species = other.species }
        if other.gender != gender { gender = other.gender }
        if other.breed != breed { breed = other.breed }
        if other.color != color { color = other.color }
        if other.notes != notes { notes = other.notes }
        if other.behaviorTagsRaw != behaviorTagsRaw { behaviorTagsRaw = other.behaviorTagsRaw }
        if other.photoData != nil { photoData = other.photoData }
        if other.thumbnailData != nil { thumbnailData = other.thumbnailData }
        updatedAt = other.updatedAt
        lastModifiedBy = other.lastModifiedBy
    }
}
