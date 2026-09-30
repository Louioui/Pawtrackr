import Foundation

/// Shared loyalty wording. Keys are literals so LocalizationTests can see them.
enum LoyaltyCopy {
    /// "1 point" / "25 points".
    static func points(_ count: Int) -> String {
        if count == 1 {
            return AppLocalization.localized("loyalty.points.one", value: "1 point")
        }
        return String(format: AppLocalization.localized("loyalty.points_fmt", value: "%d points"), count)
    }

    /// A reward's name for display. The built-in rewards (2.0 and the 1.x
    /// starter set), and templates still carrying one's exact title and cost
    /// (seeded, not edited), show translated. Anything the salon wrote shows
    /// as written.
    static func title(for reward: LoyaltyReward) -> String {
        let knownRewards = LoyaltyReward.builtInCatalog + LoyaltyReward.legacyStarterCatalog
        let builtIn = knownRewards.first { $0.id == reward.id }
            ?? knownRewards.first { $0.title == reward.title && $0.pointCost == reward.pointCost }
        guard let builtIn else { return reward.title }
        return localizedTitle(for: builtIn)
    }

    /// Literal keys, so LocalizationTests can see them.
    static func localizedTitle(for reward: LoyaltyReward) -> String {
        switch reward.id {
        case "five-off":
            return AppLocalization.localized("loyalty.reward.five_off", value: reward.title)
        case "twenty-off":
            return AppLocalization.localized("loyalty.reward.twenty_off", value: reward.title)
        case "quarter-off":
            return AppLocalization.localized("loyalty.reward.quarter_off", value: reward.title)
        case "free-bath":
            return AppLocalization.localized("loyalty.reward.free_bath", value: reward.title)
        case "visit-credit-5":
            return AppLocalization.localized("onboarding.loyalty_sim.reward.visit_credit_5", value: reward.title)
        case "visit-credit-10":
            return AppLocalization.localized("onboarding.loyalty_sim.reward.visit_credit_10", value: reward.title)
        case "addon-discount-15":
            return AppLocalization.localized("onboarding.loyalty_sim.reward.addon_discount_15", value: reward.title)
        case "groom-credit-20":
            return AppLocalization.localized("onboarding.loyalty_sim.reward.groom_credit_20", value: reward.title)
        case "basic-groom-credit":
            return AppLocalization.localized("onboarding.loyalty_sim.reward.basic_groom_credit", value: reward.title)
        default:
            return reward.title
        }
    }
}
