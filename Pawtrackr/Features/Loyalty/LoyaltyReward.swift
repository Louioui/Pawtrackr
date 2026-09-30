import Foundation

/// A reward a client can spend points on: a built-in starter reward, or a
/// display copy of one of the salon's `LoyaltyRewardTemplate` rows.
struct LoyaltyReward: Identifiable, Hashable, Sendable {
    enum Style: String, Hashable, Sendable {
        case credit
        case care
        case upgrade
        case vip
    }

    /// What the reward takes off a checkout. Rewards are cash-off only: a
    /// fixed amount, a percentage of the services, or the price of the
    /// salon's Bath service. `.manual` rewards (the salon's own, written
    /// before Loyalty 2.0) deduct points but leave the price to the groomer.
    enum Benefit: Hashable, Sendable {
        case manual
        case amountOff(Decimal)
        case percentOff(Decimal)
        case freeBath

        /// Raw storage for `LoyaltyRewardTemplate.benefitKindRaw`.
        var kindRaw: String {
            switch self {
            case .manual: ""
            case .amountOff: "amountOff"
            case .percentOff: "percentOff"
            case .freeBath: "freeBath"
            }
        }

        /// Raw storage for `LoyaltyRewardTemplate.benefitValue`: dollars for
        /// `.amountOff`, percent for `.percentOff`, zero otherwise.
        var value: Decimal {
            switch self {
            case .manual, .freeBath: .zero
            case .amountOff(let amount): amount
            case .percentOff(let percent): percent
            }
        }

        /// Rebuilds a benefit from template storage. Unknown kinds (a newer
        /// app version's value arriving over CloudKit) read as `.manual`, so
        /// an old build never takes money off it doesn't understand.
        init(kindRaw: String, value: Decimal) {
            switch kindRaw {
            case "amountOff" where value > .zero:
                self = .amountOff(value)
            case "percentOff" where value > .zero:
                self = .percentOff(min(value, Decimal(100)))
            case "freeBath":
                self = .freeBath
            default:
                self = .manual
            }
        }

        /// True when checkout can take this reward off the ticket by itself.
        var appliesAtCheckout: Bool {
            self != .manual
        }
    }

    let id: String
    let title: String
    let detail: String
    let pointCost: Int
    let systemImage: String
    let style: Style
    let benefit: Benefit

    init(
        id: String,
        title: String,
        detail: String,
        pointCost: Int,
        systemImage: String,
        style: Style,
        benefit: Benefit = .manual
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.pointCost = pointCost
        self.systemImage = systemImage
        self.style = style
        self.benefit = benefit
    }

    /// The Loyalty 2.0 starter catalog: four cash-off rewards, cheapest first.
    /// New salons are seeded with it, and salons still on the untouched 1.x
    /// catalog are moved to it (`LoyaltyCatalogUpgrade`).
    static let builtInCatalog: [LoyaltyReward] = [
        LoyaltyReward(
            id: "five-off",
            title: "$5 Off",
            detail: "Takes $5 off any checkout.",
            pointCost: 50,
            systemImage: "dollarsign.circle.fill",
            style: .credit,
            benefit: .amountOff(Decimal(5))
        ),
        LoyaltyReward(
            id: "twenty-off",
            title: "$20 Off",
            detail: "Takes $20 off any checkout.",
            pointCost: 200,
            systemImage: "banknote.fill",
            style: .vip,
            benefit: .amountOff(Decimal(20))
        ),
        LoyaltyReward(
            id: "quarter-off",
            title: "25% Off",
            detail: "Takes 25% off the services on one checkout. Tips aren't discounted.",
            pointCost: 250,
            systemImage: "percent",
            style: .upgrade,
            benefit: .percentOff(Decimal(25))
        ),
        LoyaltyReward(
            id: "free-bath",
            title: "Free Bath",
            detail: "Takes the price of your Bath service off one checkout.",
            pointCost: 400,
            systemImage: "bathtub.fill",
            style: .care,
            benefit: .freeBath
        )
    ]

    /// The 1.x starter catalog, kept only to recognize salons that never
    /// edited it (so they can be moved to 2.0) and to translate its titles.
    static let legacyStarterCatalog: [LoyaltyReward] = [
        LoyaltyReward(id: "visit-credit-5", title: "$5 Visit Credit", detail: "Apply a small thank-you discount at checkout.", pointCost: 50, systemImage: "ticket.fill", style: .credit),
        LoyaltyReward(id: "visit-credit-10", title: "$10 Visit Credit", detail: "Reward regular clients with credit toward any groom.", pointCost: 100, systemImage: "banknote.fill", style: .credit),
        LoyaltyReward(id: "addon-discount-15", title: "15% Off Add-On", detail: "Discount a nail grind, blueberry facial, or similar add-on.", pointCost: 150, systemImage: "percent", style: .upgrade),
        LoyaltyReward(id: "groom-credit-20", title: "$20 Groom Credit", detail: "A higher-value credit for loyal repeat clients.", pointCost: 200, systemImage: "creditcard.fill", style: .credit),
        LoyaltyReward(id: "basic-groom-credit", title: "Free Basic Groom Credit", detail: "A premium reward that covers a future basic groom credit.", pointCost: 500, systemImage: "crown.fill", style: .vip)
    ]

    /// Returns true when the supplied balance can cover this reward.
    func isRedeemable(with balance: Int) -> Bool {
        balance >= pointCost
    }

    /// Points still needed before this reward unlocks (zero once it has).
    func pointsNeeded(from balance: Int) -> Int {
        max(0, pointCost - balance)
    }
}

/// Money math for rewards applied at checkout. Decimal only.
enum LoyaltyRewardPricing {
    /// What `benefit` takes off a ticket whose services come to `subtotal`
    /// (tip excluded), or nil when it can't discount this ticket. Never more
    /// than the subtotal, so a reward can't produce a negative charge.
    static func discount(for benefit: LoyaltyReward.Benefit, subtotal: Decimal, bathPrice: Decimal?) -> Decimal? {
        let subtotal = subtotal.roundedMoney()
        guard subtotal > .zero else { return nil }

        let raw: Decimal
        switch benefit {
        case .manual:
            return nil
        case .amountOff(let amount):
            guard amount > .zero else { return nil }
            raw = amount
        case .percentOff(let percent):
            guard percent > .zero else { return nil }
            raw = subtotal * min(percent, Decimal(100)) / Decimal(100)
        case .freeBath:
            guard let bathPrice, bathPrice > .zero else { return nil }
            raw = bathPrice
        }
        return min(raw.roundedMoney(), subtotal)
    }
}

/// Which rewards a client can pick right now. Every loyalty screen and
/// checkout read the catalog through here, so they always agree.
enum LoyaltyRewardCatalog {
    /// The salon's enabled templates in their order; the built-in starter
    /// catalog while no template exists yet (what `ensureLoyaltyDefaults`
    /// seeds); nothing while the catalog is turned off. All templates
    /// switched off is not the same as none: it shows nothing.
    static func active(templates: [LoyaltyRewardTemplate], config: LoyaltyConfigSnapshot) -> [LoyaltyReward] {
        guard config.isRewardsCatalogEnabled else { return [] }
        guard !templates.isEmpty else { return LoyaltyReward.builtInCatalog }
        return templates
            .filter(\.isEnabled)
            .sorted { $0.sortOrder < $1.sortOrder }
            .map(\.displayReward)
    }

    /// Rewards cheapest first; ties by title.
    static func byCost(_ rewards: [LoyaltyReward]) -> [LoyaltyReward] {
        rewards.sorted { first, second in
            if first.pointCost == second.pointCost {
                return first.title.localizedStandardCompare(second.title) == .orderedAscending
            }
            return first.pointCost < second.pointCost
        }
    }
}
