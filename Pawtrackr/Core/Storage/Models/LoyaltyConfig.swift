//
//  LoyaltyConfig.swift
//  Pawtrackr
//
//  CloudKit-safe configuration for client-owned loyalty earning and redemption.
//

import Foundation
import SwiftData

enum LoyaltyEarnMode: String, CaseIterable, Sendable {
    case pointsPerDollar
    case flatPerVisit
}

struct LoyaltyConfigSnapshot: Equatable, Sendable {
    var earnMode: LoyaltyEarnMode
    var pointsPerDollar: Decimal
    var pointsPerVisit: Int
    var redemptionThreshold: Int
    var isRewardsCatalogEnabled: Bool

    static let `default` = LoyaltyConfigSnapshot(
        earnMode: .pointsPerDollar,
        pointsPerDollar: Decimal(1),
        pointsPerVisit: 20,
        redemptionThreshold: 100,
        isRewardsCatalogEnabled: true
    )

    init(
        earnMode: LoyaltyEarnMode,
        pointsPerDollar: Decimal,
        pointsPerVisit: Int,
        redemptionThreshold: Int,
        isRewardsCatalogEnabled: Bool
    ) {
        self.earnMode = earnMode
        self.pointsPerDollar = max(pointsPerDollar, .zero)
        self.pointsPerVisit = max(0, pointsPerVisit)
        self.redemptionThreshold = max(1, redemptionThreshold)
        self.isRewardsCatalogEnabled = isRewardsCatalogEnabled
    }

    init(config: LoyaltyConfig?) {
        guard let config else {
            self = .default
            return
        }

        self.init(
            earnMode: config.earnMode,
            pointsPerDollar: config.pointsPerDollar,
            pointsPerVisit: config.pointsPerVisit,
            redemptionThreshold: config.redemptionThreshold,
            isRewardsCatalogEnabled: config.isRewardsCatalogEnabled
        )
    }
}

enum LoyaltyConfigResolver {
    static func snapshot(in context: ModelContext) -> LoyaltyConfigSnapshot {
        var descriptor = FetchDescriptor<LoyaltyConfig>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        descriptor.fetchLimit = 1
        let config = try? context.fetch(descriptor).first
        return LoyaltyConfigSnapshot(config: config)
    }
}

@Model
final class LoyaltyConfig {
    // Non-optional defaults keep CloudKit partial records decodable.
    var uuid: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var lastModifiedBy: UUID = DeviceIdentity.currentID

    var earnModeRaw: String = LoyaltyEarnMode.pointsPerDollar.rawValue
    var pointsPerDollar: Decimal = Decimal(1)
    var pointsPerVisit: Int = 20
    var redemptionThreshold: Int = 100
    var isRewardsCatalogEnabled: Bool = true

    @Transient
    var earnMode: LoyaltyEarnMode {
        get { LoyaltyEarnMode(rawValue: earnModeRaw) ?? .pointsPerDollar }
        set {
            earnModeRaw = newValue.rawValue
            markModified()
        }
    }

    @Transient
    var snapshot: LoyaltyConfigSnapshot {
        LoyaltyConfigSnapshot(config: self)
    }

    init() {
        uuid = UUID()
        createdAt = .now
        updatedAt = .now
        lastModifiedBy = DeviceIdentity.currentID
    }

    func setPointsPerDollar(_ value: Decimal) {
        pointsPerDollar = max(value, .zero)
        markModified()
    }

    func setEarnMode(_ mode: LoyaltyEarnMode) {
        earnModeRaw = mode.rawValue
        markModified()
    }

    func setPointsPerVisit(_ value: Int) {
        pointsPerVisit = max(0, value)
        markModified()
    }

    func setRedemptionThreshold(_ value: Int) {
        redemptionThreshold = max(1, value)
        markModified()
    }

    func setRewardsCatalogEnabled(_ value: Bool) {
        isRewardsCatalogEnabled = value
        markModified()
    }

    func markModified() {
        updatedAt = .now
        lastModifiedBy = DeviceIdentity.currentID
    }
}

extension LoyaltyConfig: Identifiable {
    var id: UUID { uuid }
}
