//
//  LoyaltyLedgerEntry.swift
//  Pawtrackr
//
//  Append-only audit trail for every loyalty balance mutation: checkout
//  earns, reward redemptions, and manual staff adjustments.
//
//  Like CheckoutTransaction, entries link to their client/visit by UUID —
//  no SwiftData relationship — so the audit history survives cascade
//  deletes and never participates in CloudKit relationship repair.
//

import Foundation
import SwiftData

@Model
final class LoyaltyLedgerEntry {
    #Index<LoyaltyLedgerEntry>([\.clientUUID, \.createdAt])

    // MARK: - Identity & Timestamps
    // NOTE: Non-optional properties have defaults so CloudKit can rehydrate
    // partial records. App init paths always overwrite these.
    var uuid: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var lastModifiedBy: UUID = DeviceIdentity.currentID

    // MARK: - Linkage
    var clientUUID: UUID = UUID()
    /// Set for `.earned` entries; identifies the visit so re-checkouts can
    /// update the same entry instead of appending a duplicate.
    var visitUUID: UUID?

    // MARK: - Mutation
    /// Signed point delta applied to the client balance.
    var points: Int = 0
    /// Client balance immediately after this mutation, when known.
    /// Nil for entries backfilled from pre-ledger history.
    var balanceAfter: Int?
    /// Human context: reward title, adjustment note, or the pet's name for earns.
    var reason: String?

    // MARK: - Kind (raw string storage; Codable enums crash @Query on bad CloudKit values)
    var kindRaw: String = Kind.earned.rawValue

    enum Kind: String, CaseIterable, Sendable {
        case earned
        case redeemed
        case adjusted
    }

    @Transient
    var kind: Kind {
        get { Kind(rawValue: kindRaw) ?? .adjusted }
        set { kindRaw = newValue.rawValue }
    }

    // MARK: - Init
    init(
        kind: Kind,
        points: Int,
        clientUUID: UUID,
        visitUUID: UUID? = nil,
        balanceAfter: Int? = nil,
        reason: String? = nil,
        createdAt: Date = .now
    ) {
        self.uuid = UUID()
        self.kindRaw = kind.rawValue
        self.points = points
        self.clientUUID = clientUUID
        self.visitUUID = visitUUID
        self.balanceAfter = balanceAfter
        self.reason = reason
        self.createdAt = createdAt
        self.updatedAt = .now
        self.lastModifiedBy = DeviceIdentity.currentID
    }

    func markModified() {
        updatedAt = .now
        lastModifiedBy = DeviceIdentity.currentID
    }
}
