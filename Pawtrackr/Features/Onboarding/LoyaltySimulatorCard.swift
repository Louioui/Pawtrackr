//
//  LoyaltySimulatorCard.swift
//  Pawtrackr
//
//  A plain-language explainer of the loyalty program with a live preview.
//  Points come from `LoyaltyEngine.preview`, the same function checkout's
//  `LoyaltyCheckoutProcessor.applyEarnings` awards, applied to the salon's
//  own rules (`LoyaltyConfigResolver`) and reward templates. Nothing here
//  writes to the store.
//
//  Shown on the onboarding Loyalty step and in Settings > Loyalty.
//

import SwiftUI
import SwiftData

struct LoyaltySimulatorCard: View {
    /// The currency symbol money is shown with. Onboarding passes the one
    /// picked on the Regional step, which isn't saved yet. `nil` uses the
    /// saved setting.
    var currencySymbol: String? = nil

    @Environment(AppSettings.self) private var appSettings
    @Query(sort: \LoyaltyConfig.createdAt, order: .forward) private var configs: [LoyaltyConfig]
    @Query(sort: \LoyaltyRewardTemplate.sortOrder, order: .forward) private var templates: [LoyaltyRewardTemplate]

    /// Money stays Decimal. The slider only moves in whole steps of 5.
    @State private var ticket: Decimal = 80
    @State private var tier: LoyaltyTier = .bronze
    @State private var isRebook = false

    static let ticketRange: ClosedRange<Double> = 0...200
    static let ticketStep: Double = 5

    private var config: LoyaltyConfigSnapshot {
        LoyaltyConfigResolver.snapshot(from: configs)
    }

    private var symbol: String {
        let chosen = (currencySymbol ?? appSettings.currencySymbol).trimmingCharacters(in: .whitespacesAndNewlines)
        return chosen.isEmpty ? "$" : chosen
    }

    private var preview: LoyaltyEarnPreview {
        LoyaltyEngine.preview(ticket: ticket, config: config, tier: tier, rebook: isRebook)
    }

    private var rewards: [LoyaltyReward] {
        Self.rewards(templates: templates, config: config)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(
                AppLocalization.localized("onboarding.loyalty_sim.title", value: "Loyalty Points"),
                systemImage: "giftcard.fill"
            )
            .font(.headline)

            explainer
            tryIt
            rewardsSection

            Text(LoyaltyExplainer.rulesSource(hasSavedRules: !configs.isEmpty))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.ColorToken.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .hairlineBorder(DS.ColorToken.border, cornerRadius: 14)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("loyaltySimulator.card")
    }

    // MARK: - How points work

    private var explainer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppLocalization.localized("loyalty.preview.how_title", value: "How points work"))
                .font(.subheadline.weight(.semibold))

            explainerRow(systemImage: "sparkles", text: LoyaltyExplainer.earning(config: config, currencySymbol: symbol))
            explainerRow(systemImage: "arrow.up.right.circle", text: LoyaltyExplainer.tiers)
            explainerRow(systemImage: "calendar.badge.clock", text: LoyaltyExplainer.rebook)
            explainerRow(systemImage: "gift", text: LoyaltyExplainer.redeeming(config: config))
        }
    }

    private func explainerRow(systemImage: String, text: String) -> some View {
        Label {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(DS.ColorToken.primary)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    // MARK: - Try it

    private var ticketBinding: Binding<Double> {
        Binding(
            get: { NSDecimalNumber(decimal: ticket).doubleValue },
            set: { newValue in
                // Snap to a whole step, then hold it as an exact Decimal.
                let steps = Int((newValue / Self.ticketStep).rounded())
                let snapped = Decimal(steps) * Decimal(Int(Self.ticketStep))
                if snapped != ticket { ticket = snapped }
            }
        )
    }

    private var tryIt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppLocalization.localized("loyalty.preview.try_title", value: "Try it"))
                .font(.subheadline.weight(.semibold))

            HStack {
                Text(AppLocalization.localized("loyalty.preview.ticket", value: "Checkout total, tip included"))
                    .font(.subheadline)
                Spacer(minLength: 8)
                Text(LoyaltyExplainer.money(ticket, symbol: symbol))
                    .monospacedDigit()
                    .fontWeight(.semibold)
            }
            Slider(value: ticketBinding, in: Self.ticketRange, step: Self.ticketStep)
                .accessibilityLabel(AppLocalization.localized("loyalty.preview.ticket", value: "Checkout total, tip included"))
                .accessibilityValue(LoyaltyExplainer.money(ticket, symbol: symbol))
                .accessibilityIdentifier("onboarding.loyaltySimulator.slider")

            HStack {
                Text(AppLocalization.localized("loyalty.preview.tier", value: "Client tier"))
                    .font(.subheadline)
                Spacer(minLength: 8)
                Picker(AppLocalization.localized("loyalty.preview.tier", value: "Client tier"), selection: $tier) {
                    ForEach(LoyaltyTier.allCases, id: \.self) { tier in
                        Text(LoyaltyExplainer.tierChoice(tier)).tag(tier)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .accessibilityIdentifier("loyaltySimulator.tier")
            }

            Toggle(isOn: $isRebook) {
                Text(LoyaltyExplainer.rebookToggle)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityIdentifier("loyaltySimulator.rebook")

            result
        }
        .padding(12)
        .background(DS.ColorToken.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var result: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(LoyaltyCopy.points(preview.total), systemImage: "star.circle.fill")
                .font(.title3.weight(.bold))
                .foregroundStyle(DS.ColorToken.primary)

            ForEach(LoyaltyExplainer.breakdown(preview, config: config), id: \.self) { line in
                Text(line)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("loyaltySimulator.result")
    }

    // MARK: - Rewards

    @ViewBuilder
    private var rewardsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(templates.isEmpty
                 ? AppLocalization.localized("loyalty.preview.rewards_starter", value: "Starter rewards")
                 : AppLocalization.localized("loyalty.preview.rewards_salon", value: "Your rewards"))
                .font(.subheadline.weight(.semibold))

            if rewards.isEmpty {
                Text(config.isRewardsCatalogEnabled
                     ? AppLocalization.localized("loyalty.preview.rewards_none", value: "No rewards are turned on. Clients keep earning points.")
                     : AppLocalization.localized("loyalty.preview.rewards_paused", value: "Rewards are paused. Clients keep earning points."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                FlowLayout(spacing: 8, rowSpacing: 8) {
                    ForEach(rewards) { reward in
                        let covered = preview.total >= reward.pointCost
                        Label(
                            String(
                                format: AppLocalization.localized("loyalty.preview.reward_chip_fmt", value: "%1$@ · %2$@"),
                                Self.displayTitle(for: reward),
                                LoyaltyCopy.points(reward.pointCost)
                            ),
                            systemImage: covered ? "checkmark.circle.fill" : "circle"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(covered ? DS.ColorToken.success : .secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.secondary.opacity(0.10), in: Capsule())
                    }
                }
                Text(AppLocalization.localized("loyalty.preview.rewards_hint", value: "A check means this one visit earns enough points for it."))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Pure helpers

    /// The rewards a client can pick, as the Rewards Catalog lists them: the
    /// salon's enabled templates in their order, the built-in starter catalog
    /// while no template exists yet (what `ensureLoyaltyDefaults` seeds), and
    /// nothing while the catalog is turned off.
    static func rewards(templates: [LoyaltyRewardTemplate], config: LoyaltyConfigSnapshot) -> [LoyaltyReward] {
        LoyaltyRewardCatalog.active(templates: templates, config: config)
    }

    /// The starter catalog, in order, with each reward's point cost.
    static var rewardLadder: [(points: Int, title: String)] {
        LoyaltyReward.builtInCatalog.map { ($0.pointCost, displayTitle(for: $0)) }
    }

    /// A reward's name for display. The built-in rewards, and templates still
    /// carrying a built-in reward's exact title and cost (seeded, not edited),
    /// show translated. Anything the salon wrote shows as written.
    static func displayTitle(for reward: LoyaltyReward) -> String {
        LoyaltyCopy.title(for: reward)
    }
}

/// The loyalty explainer's sentences. Each one states what the engine and
/// the Rewards Catalog actually do, nothing more.
enum LoyaltyExplainer {
    /// How a checkout earns, for the current rules.
    static func earning(config: LoyaltyConfigSnapshot, currencySymbol: String) -> String {
        switch config.earnMode {
        case .pointsPerDollar:
            guard config.pointsPerDollar > .zero else {
                return String(
                    format: AppLocalization.localized(
                        "loyalty.preview.earn_rate_off_fmt",
                        value: "Checkouts earn no points right now: the rule is 0 points per %@."
                    ),
                    money(1, symbol: currencySymbol)
                )
            }
            return String(
                format: AppLocalization.localized(
                    "loyalty.preview.earn_rate_fmt",
                    value: "Each checkout earns %1$@ for every %2$@ the client pays, tip included. Points are rounded down to a whole number."
                ),
                rate(config.pointsPerDollar),
                money(1, symbol: currencySymbol)
            )
        case .flatPerVisit:
            guard config.pointsPerVisit > 0 else {
                return AppLocalization.localized(
                    "loyalty.preview.earn_flat_off",
                    value: "Checkouts earn no points right now: the rule is 0 points per visit."
                )
            }
            return String(
                format: AppLocalization.localized(
                    "loyalty.preview.earn_flat_fmt",
                    value: "Each checkout earns %@, whatever the total. The tip doesn't change it."
                ),
                LoyaltyCopy.points(config.pointsPerVisit)
            )
        }
    }

    /// The tier ladder: thresholds and what a tier does.
    static var tiers: String {
        String(
            format: AppLocalization.localized(
                "loyalty.preview.tiers_fmt",
                value: "Points earned at checkout move a client up: Silver at %1$@, Gold at %2$@ and Platinum at %3$@. Each tier multiplies the points of every visit. Spending points never lowers a tier."
            ),
            count(LoyaltyTier.silver.threshold),
            count(LoyaltyTier.gold.threshold),
            count(LoyaltyTier.platinum.threshold)
        )
    }

    /// The rebook bonus.
    static var rebook: String {
        String(
            format: AppLocalization.localized(
                "loyalty.preview.rebook_fmt",
                value: "A visit that earns points gets %1$@ more when the client's last visit ended %2$d days ago or less."
            ),
            LoyaltyCopy.points(LoyaltyEngine.rebookBonusPoints),
            LoyaltyEngine.rebookWindowDays
        )
    }

    /// How points are spent. Redeeming only lowers the balance: the reward
    /// itself is given by the groomer.
    static func redeeming(config: LoyaltyConfigSnapshot) -> String {
        guard config.isRewardsCatalogEnabled else {
            return AppLocalization.localized(
                "loyalty.preview.redeem_paused",
                value: "Rewards are paused, so points can't be redeemed right now. Clients keep their balance."
            )
        }
        return AppLocalization.localized(
            "loyalty.preview.redeem",
            value: "To redeem, open Loyalty & Rewards on the client's profile and pick a reward. Its points come off the balance. Then give the reward yourself, for example as a discount at checkout."
        )
    }

    static var rebookToggle: String {
        String(
            format: AppLocalization.localized("loyalty.preview.rebook_toggle_fmt", value: "Back within %d days"),
            LoyaltyEngine.rebookWindowDays
        )
    }

    /// "Silver ×1.1" for the tier picker.
    static func tierChoice(_ tier: LoyaltyTier) -> String {
        String(
            format: AppLocalization.localized("loyalty.preview.tier_choice_fmt", value: "%1$@ %2$@"),
            tier.displayName,
            tier.earnRateText
        )
    }

    /// The lines under the total, e.g. "From the total: 80 points",
    /// "Silver ×1.1: 88 points", "Rebook bonus: +20 points".
    static func breakdown(_ preview: LoyaltyEarnPreview, config: LoyaltyConfigSnapshot) -> [String] {
        var lines: [String] = []
        switch config.earnMode {
        case .pointsPerDollar:
            lines.append(String(
                format: AppLocalization.localized("loyalty.preview.base_total_fmt", value: "From the total: %@"),
                LoyaltyCopy.points(preview.basePoints)
            ))
        case .flatPerVisit:
            lines.append(String(
                format: AppLocalization.localized("loyalty.preview.base_flat_fmt", value: "Per visit: %@"),
                LoyaltyCopy.points(preview.basePoints)
            ))
        }
        if preview.tier != .bronze, preview.basePoints > 0 {
            lines.append(String(
                format: AppLocalization.localized("loyalty.preview.tier_line_fmt", value: "%1$@: %2$@"),
                tierChoice(preview.tier),
                LoyaltyCopy.points(preview.tierPoints)
            ))
        }
        if preview.rebookBonus > 0 {
            lines.append(String(
                format: AppLocalization.localized("loyalty.preview.rebook_line_fmt", value: "Rebook bonus: +%@"),
                LoyaltyCopy.points(preview.rebookBonus)
            ))
        }
        return lines
    }

    /// Where the rules shown come from.
    static func rulesSource(hasSavedRules: Bool) -> String {
        hasSavedRules
            ? AppLocalization.localized(
                "loyalty.preview.rules_saved",
                value: "These are your salon's current rules. Checkout awards points with this same math."
            )
            : AppLocalization.localized(
                "loyalty.preview.rules_default",
                value: "These are the default rules. Checkout awards points with this same math, and you can change the rules in Settings > Loyalty."
            )
    }

    /// Money in the salon's currency symbol, without Double math.
    static func money(_ amount: Decimal, symbol: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = .current
        formatter.currencySymbol = symbol
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(symbol)\(amount)"
    }

    /// "1 point", "2 points", or "1.5 points" for a fractional rate.
    static func rate(_ pointsPerUnit: Decimal) -> String {
        var value = pointsPerUnit
        var whole = Decimal()
        NSDecimalRound(&whole, &value, 0, .down)
        if whole == pointsPerUnit {
            return LoyaltyCopy.points((whole as NSDecimalNumber).intValue)
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = AppLocalization.currentLocale
        formatter.maximumFractionDigits = 2
        let number = formatter.string(from: pointsPerUnit as NSDecimalNumber) ?? "\(pointsPerUnit)"
        return String(format: AppLocalization.localized("loyalty.preview.points_decimal_fmt", value: "%@ points"), number)
    }

    /// "1,500", grouped for the app's language.
    static func count(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = AppLocalization.currentLocale
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
