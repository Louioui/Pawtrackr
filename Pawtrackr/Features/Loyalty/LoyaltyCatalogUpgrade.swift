//
//  LoyaltyCatalogUpgrade.swift
//  Pawtrackr
//
//  Moves salons still on the untouched 1.x starter rewards to the Loyalty 2.0
//  catalog ($5 Off, $20 Off, 25% Off, Free Bath). A catalog the salon has
//  changed in any way is left exactly as it is.
//

import Foundation
import SwiftData

enum LoyaltyCatalogUpgrade {
    /// The rows to keep, one per 1.x starter reward in catalog order, when
    /// `templates` are only untouched 1.x starter rows (same titles and costs,
    /// enabled, no 2.0 benefit) covering the whole starter set. Two devices
    /// that each seeded before syncing hold every row twice; the copy with the
    /// smallest UUID is kept, so every device picks the same one. Nil when the
    /// salon changed anything.
    static func untouchedLegacyRows(_ templates: [LoyaltyRewardTemplate]) -> [LoyaltyRewardTemplate]? {
        let legacy = LoyaltyReward.legacyStarterCatalog
        guard !templates.isEmpty else { return nil }

        var keepers: [LoyaltyRewardTemplate?] = Array(repeating: nil, count: legacy.count)
        for template in templates {
            guard template.isEnabled, template.benefitKindRaw.isEmpty,
                  let index = legacy.firstIndex(where: { $0.title == template.title && $0.pointCost == template.pointCost })
            else { return nil }
            if let kept = keepers[index], kept.uuid.uuidString <= template.uuid.uuidString { continue }
            keepers[index] = template
        }
        let rows = keepers.compactMap { $0 }
        return rows.count == legacy.count ? rows : nil
    }

    static func isUntouchedLegacyCatalog(_ templates: [LoyaltyRewardTemplate]) -> Bool {
        untouchedLegacyRows(templates) != nil
    }

    /// Rewrites an untouched 1.x catalog as the 2.0 catalog in place and
    /// deletes the leftover row and any duplicate copies. Returns true when it
    /// changed anything; the caller saves. Updating rows in place keeps two
    /// devices that run this at once converging on one catalog.
    @discardableResult
    static func upgradeIfUntouched(_ templates: [LoyaltyRewardTemplate], in context: ModelContext) -> Bool {
        guard let rows = untouchedLegacyRows(templates) else { return false }

        let kept = Set(rows.map(\.uuid))
        let catalog = LoyaltyReward.builtInCatalog
        for (index, template) in rows.enumerated() {
            if index < catalog.count {
                template.adopt(catalog[index], sortOrder: index)
            } else {
                context.delete(template)
            }
        }
        for template in templates where !kept.contains(template.uuid) {
            context.delete(template)
        }
        return true
    }
}
