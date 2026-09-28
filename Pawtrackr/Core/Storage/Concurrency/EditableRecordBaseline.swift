//
//  EditableRecordBaseline.swift
//  Pawtrackr
//

import Foundation
import CryptoKit

enum ConflictResolutionChoice: Equatable, Sendable {
    case useLocal
    case useRemote
    case merge
}

struct EditableRecordBaseline: Equatable, Sendable {
    let recordUUID: UUID
    let updatedAt: Date
    let lastModifiedBy: UUID
    let fieldHashes: [String: String]

    init(recordUUID: UUID, updatedAt: Date, lastModifiedBy: UUID, fields: [String: String?]) {
        self.recordUUID = recordUUID
        self.updatedAt = updatedAt
        self.lastModifiedBy = lastModifiedBy
        self.fieldHashes = fields.mapValues { Self.hash($0 ?? "") }
    }

    func changedFields(comparedTo fields: [String: String?]) -> Set<String> {
        Set(fields.compactMap { key, value in
            fieldHashes[key] == Self.hash(value ?? "") ? nil : key
        })
    }

    func isStale(remoteUpdatedAt: Date, remoteModifiedBy: UUID) -> Bool {
        remoteUpdatedAt > updatedAt && remoteModifiedBy != lastModifiedBy
    }

    private static func hash(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
