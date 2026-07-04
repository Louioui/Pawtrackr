import Foundation

/// A built-in, schema-free reward catalog entry for the premium loyalty UI.
struct LoyaltyReward: Identifiable, Hashable, Sendable {
    enum Style: String, Hashable, Sendable {
        case credit
        case care
        case upgrade
        case vip
    }

    let id: String
    let title: String
    let detail: String
    let pointCost: Int
    let systemImage: String
    let style: Style

    /// The starter catalog used until configurable rewards land in the V2 loyalty schema.
    static let builtInCatalog: [LoyaltyReward] = [
        LoyaltyReward(
            id: "salon-credit-10",
            title: "$10 Salon Credit",
            detail: "Apply toward the next completed checkout.",
            pointCost: 100,
            systemImage: "ticket.fill",
            style: .credit
        ),
        LoyaltyReward(
            id: "deep-conditioning",
            title: "Deep-Conditioning Treatment",
            detail: "A premium coat-care add-on for a returning client.",
            pointCost: 200,
            systemImage: "drop.fill",
            style: .care
        ),
        LoyaltyReward(
            id: "deshedding-upgrade",
            title: "Deshedding Upgrade",
            detail: "A complimentary seasonal shed-control upgrade.",
            pointCost: 350,
            systemImage: "scissors",
            style: .upgrade
        ),
        LoyaltyReward(
            id: "vip-spa-package",
            title: "VIP Spa Package",
            detail: "Bundle a high-value add-on into the client's next visit.",
            pointCost: 500,
            systemImage: "sparkles",
            style: .vip
        )
    ]

    /// Returns true when the supplied balance can cover this reward.
    func isRedeemable(with balance: Int) -> Bool {
        balance >= pointCost
    }
}
