//
//  LoyaltyRewardTemplate.swift
//  Pawtrackr
//
//  Owner-editable reward definitions for the premium loyalty catalog.
//

import Foundation
import SwiftData

@Model
final class LoyaltyRewardTemplate {
    // Non-optional defaults keep CloudKit partial records decodable.
    var uuid: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var lastModifiedBy: UUID = DeviceIdentity.currentID

    var title: String = ""
    var detail: String = ""
    var pointCost: Int = 1
    var systemImage: String = "gift.fill"
    var styleRaw: String = LoyaltyReward.Style.credit.rawValue
    var sortOrder: Int = 0
    var isEnabled: Bool = true
    /// Loyalty 2.0: what the reward takes off a checkout. Added with
    /// defaults (additive, ADR-0004); "" is a manual reward, which is what
    /// every row written before 2.0 reads as.
    var benefitKindRaw: String = ""
    /// Dollars for an amount-off reward, percent for a percent-off one.
    var benefitValue: Decimal = Decimal(0)

    @Transient
    var style: LoyaltyReward.Style {
        get { LoyaltyReward.Style(rawValue: styleRaw) ?? .credit }
        set {
            styleRaw = newValue.rawValue
            markModified()
        }
    }

    @Transient
    var benefit: LoyaltyReward.Benefit {
        get { LoyaltyReward.Benefit(kindRaw: benefitKindRaw, value: benefitValue) }
        set {
            benefitKindRaw = newValue.kindRaw
            benefitValue = newValue.value
            markModified()
        }
    }

    init(
        title: String,
        detail: String,
        pointCost: Int,
        systemImage: String,
        styleRaw: String,
        sortOrder: Int,
        isEnabled: Bool = true,
        benefit: LoyaltyReward.Benefit = .manual
    ) {
        uuid = UUID()
        createdAt = .now
        updatedAt = .now
        lastModifiedBy = DeviceIdentity.currentID
        self.title = TextInputLimits.clamped(title, to: TextInputLimits.name)
        self.detail = TextInputLimits.clamped(detail, to: TextInputLimits.notes)
        self.pointCost = max(1, pointCost)
        self.systemImage = Self.normalizedSystemImage(systemImage)
        self.styleRaw = LoyaltyReward.Style(rawValue: styleRaw)?.rawValue ?? LoyaltyReward.Style.credit.rawValue
        self.sortOrder = sortOrder
        self.isEnabled = isEnabled
        self.benefitKindRaw = benefit.kindRaw
        self.benefitValue = benefit.value
    }

    convenience init(reward: LoyaltyReward, sortOrder: Int) {
        self.init(
            title: reward.title,
            detail: reward.detail,
            pointCost: reward.pointCost,
            systemImage: reward.systemImage,
            styleRaw: reward.style.rawValue,
            sortOrder: sortOrder,
            benefit: reward.benefit
        )
    }

    static func seedTemplates() -> [LoyaltyRewardTemplate] {
        LoyaltyReward.builtInCatalog.enumerated().map { index, reward in
            LoyaltyRewardTemplate(reward: reward, sortOrder: index)
        }
    }

    var displayReward: LoyaltyReward {
        LoyaltyReward(
            id: uuid.uuidString,
            title: title,
            detail: detail,
            pointCost: pointCost,
            systemImage: systemImage,
            style: style,
            benefit: benefit
        )
    }

    var reward: LoyaltyReward {
        displayReward
    }

    func update(
        title: String,
        detail: String,
        pointCost: Int,
        systemImage: String,
        style: LoyaltyReward.Style,
        sortOrder: Int,
        isEnabled: Bool
    ) {
        self.title = TextInputLimits.clamped(title, to: TextInputLimits.name)
        self.detail = TextInputLimits.clamped(detail, to: TextInputLimits.notes)
        self.pointCost = max(1, pointCost)
        self.systemImage = Self.normalizedSystemImage(systemImage)
        self.styleRaw = style.rawValue
        self.sortOrder = sortOrder
        self.isEnabled = isEnabled
        markModified()
    }

    /// Rewrites this row as `reward` in place. Used to move an untouched 1.x
    /// starter row to its 2.0 replacement: updating (not deleting and
    /// re-inserting) means two devices doing it at once converge on the same
    /// values instead of uploading two catalogs.
    func adopt(_ reward: LoyaltyReward, sortOrder: Int) {
        title = TextInputLimits.clamped(reward.title, to: TextInputLimits.name)
        detail = TextInputLimits.clamped(reward.detail, to: TextInputLimits.notes)
        pointCost = max(1, reward.pointCost)
        systemImage = Self.normalizedSystemImage(reward.systemImage)
        styleRaw = reward.style.rawValue
        benefitKindRaw = reward.benefit.kindRaw
        benefitValue = reward.benefit.value
        self.sortOrder = sortOrder
        isEnabled = true
        markModified()
    }

    func setEnabled(_ value: Bool) {
        isEnabled = value
        markModified()
    }

    func markModified() {
        updatedAt = .now
        lastModifiedBy = DeviceIdentity.currentID
    }

    private static func normalizedSystemImage(_ value: String) -> String {
        let symbol = TextInputLimits.clamped(value, to: TextInputLimits.shortText)
        return symbol.isEmpty ? "gift.fill" : symbol
    }
}

extension LoyaltyRewardTemplate: Identifiable {
    var id: UUID { uuid }
}
