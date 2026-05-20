//
//  OfflineMutationBuffer.swift
//  Pawtrackr
//
//  Lightweight metadata queue for local changes made while iCloud is not
//  reachable. SwiftData still owns the durable row writes; this buffer gives
//  the sync monitor a bounded, batch-drained shadow log to surface and
//  reconcile when connectivity returns.
//

import Foundation

enum OfflineMutationBuffer {
    static let batchLimit = 40
    private static let maxRecords = 240
    private static let defaultsKey = "cloudkit.offlineMutationBuffer.v1"

    struct Record: Codable, Identifiable, Equatable, Sendable {
        let id: UUID
        let createdAt: Date
        let operation: String
        let entityName: String?
        let recordUUID: UUID?
        let changedKeys: [String]
        let deviceID: UUID
    }

    @discardableResult
    static func append(
        operation: String,
        entityName: String? = nil,
        recordUUID: UUID? = nil,
        changedKeys: [String] = []
    ) -> Int {
        var records = load()
        records.append(
            Record(
                id: UUID(),
                createdAt: Date(),
                operation: operation,
                entityName: entityName,
                recordUUID: recordUUID,
                changedKeys: stableKeys(changedKeys),
                deviceID: DeviceIdentity.currentID
            )
        )
        if records.count > maxRecords {
            records.removeFirst(records.count - maxRecords)
        }
        save(records)
        return records.count
    }

    static var count: Int {
        load().count
    }

    static func peekBatch(limit: Int = batchLimit) -> [Record] {
        Array(load().prefix(max(1, min(limit, batchLimit))))
    }

    @discardableResult
    static func remove(ids: Set<UUID>) -> Int {
        guard !ids.isEmpty else { return count }
        let remaining = load().filter { !ids.contains($0.id) }
        save(remaining)
        return remaining.count
    }

    static func remove(ids: [UUID]) -> Int {
        remove(ids: Set(ids))
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    private static func stableKeys(_ keys: [String]) -> [String] {
        Array(Set(keys.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }))
            .sorted()
    }

    private static func load() -> [Record] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let records = try? JSONDecoder().decode([Record].self, from: data) else {
            return []
        }
        return records
    }

    private static func save(_ records: [Record]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
