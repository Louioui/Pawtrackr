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
            id: "visit-credit-5",
            title: "$5 Visit Credit",
            detail: "Apply a small thank-you discount at checkout.",
            pointCost: 50,
            systemImage: "ticket.fill",
            style: .credit
        ),
        LoyaltyReward(
            id: "visit-credit-10",
            title: "$10 Visit Credit",
            detail: "Reward regular clients with credit toward any groom.",
            pointCost: 100,
            systemImage: "banknote.fill",
            style: .credit
        ),
        LoyaltyReward(
            id: "addon-discount-15",
            title: "15% Off Add-On",
            detail: "Discount a nail grind, blueberry facial, or similar add-on.",
            pointCost: 150,
            systemImage: "percent",
            style: .upgrade
        ),
        LoyaltyReward(
            id: "groom-credit-20",
            title: "$20 Groom Credit",
            detail: "A higher-value credit for loyal repeat clients.",
            pointCost: 200,
            systemImage: "creditcard.fill",
            style: .credit
        ),
        LoyaltyReward(
            id: "basic-groom-credit",
            title: "Free Basic Groom Credit",
            detail: "A premium reward that covers a future basic groom credit.",
            pointCost: 500,
            systemImage: "crown.fill",
            style: .vip
        )
    ]

    /// Returns true when the supplied balance can cover this reward.
    func isRedeemable(with balance: Int) -> Bool {
        balance >= pointCost
    }
}
