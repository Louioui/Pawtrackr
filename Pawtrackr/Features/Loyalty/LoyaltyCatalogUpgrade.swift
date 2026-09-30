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
    /// True when `templates` are the five 1.x starter rewards as seeded: same
    /// titles, costs and order, all enabled, none carrying a 2.0 benefit.
    static func isUntouchedLegacyCatalog(_ templates: [LoyaltyRewardTemplate]) -> Bool {
        let legacy = LoyaltyReward.legacyStarterCatalog
        guard templates.count == legacy.count else { return false }
        let ordered = templates.sorted { $0.sortOrder < $1.sortOrder }
        return zip(ordered, legacy).allSatisfy { template, reward in
            template.title == reward.title
                && template.pointCost == reward.pointCost
                && template.isEnabled
                && template.benefitKindRaw.isEmpty
        }
    }

    /// Rewrites an untouched 1.x catalog as the 2.0 catalog in place and
    /// deletes the leftover row. Returns true when it changed anything; the
    /// caller saves. Updating rows in place keeps two devices that run this
    /// at once converging on one catalog.
    @discardableResult
    static func upgradeIfUntouched(_ templates: [LoyaltyRewardTemplate], in context: ModelContext) -> Bool {
        guard isUntouchedLegacyCatalog(templates) else { return false }

        let ordered = templates.sorted { $0.sortOrder < $1.sortOrder }
        let catalog = LoyaltyReward.builtInCatalog
        for (index, template) in ordered.enumerated() {
            if index < catalog.count {
                template.adopt(catalog[index], sortOrder: index)
            } else {
                context.delete(template)
            }
        }
        return true
    }
}
