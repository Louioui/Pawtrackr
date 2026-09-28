//
//  LoyaltySimulatorCard.swift
//  Pawtrackr
//

import SwiftUI

struct LoyaltySimulatorCard: View {
    @State private var ticketTotal: Double = 80

    /// The rewards a new salon starts with: the same catalog, in the same
    /// order and at the same point costs, that `ensureLoyaltyDefaults` seeds.
    /// Only the names are translated for display. The seeded templates keep
    /// the catalog's own titles.
    static var rewardLadder: [(points: Int, title: String)] {
        LoyaltyReward.builtInCatalog.map { reward in
            (reward.pointCost, localizedTitle(for: reward))
        }
    }

    /// Literal keys, so LocalizationTests can see them.
    static func localizedTitle(for reward: LoyaltyReward) -> String {
        switch reward.id {
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

    private var earnedPoints: Int {
        Int(ticketTotal.rounded())
    }

    private var currencyCode: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    private var oneUnitOfCurrency: String {
        1.formatted(.currency(code: currencyCode).precision(.fractionLength(0)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(
                AppLocalization.localized("onboarding.loyalty_sim.title", value: "Loyalty Points"),
                systemImage: "giftcard.fill"
            )
            .font(.headline)

            Text(String(
                format: AppLocalization.localized(
                    "onboarding.loyalty_sim.explainer_fmt",
                    value: "Each completed visit earns points from its ticket total, 1 point per %@ by default. Clients trade points for visit credits and add-on discounts."
                ),
                oneUnitOfCurrency
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(AppLocalization.localized("onboarding.loyalty_sim.ticket", value: "Ticket"))
                    Spacer()
                    Text(ticketTotal, format: .currency(code: currencyCode))
                        .monospacedDigit()
                        .fontWeight(.semibold)
                }
                Slider(value: $ticketTotal, in: 0...200, step: 5)
                    .accessibilityIdentifier("onboarding.loyaltySimulator.slider")
                HStack {
                    Label(
                        String(
                            format: AppLocalization.localized("onboarding.loyalty_sim.points_fmt", value: "%d points"),
                            earnedPoints
                        ),
                        systemImage: "sparkles"
                    )
                    .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(AppLocalization.localized("onboarding.loyalty_sim.no_extra_math", value: "No extra math"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DS.ColorToken.success)
                }
            }
            .padding(12)
            .background(DS.ColorToken.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            FlowLayout(spacing: 8, rowSpacing: 8) {
                ForEach(Self.rewardLadder, id: \.points) { reward in
                    Label(reward.title, systemImage: earnedPoints >= reward.points ? "checkmark.circle.fill" : "circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(earnedPoints >= reward.points ? DS.ColorToken.success : .secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.secondary.opacity(0.10), in: Capsule())
                }
            }
        }
        .padding()
        .background(DS.ColorToken.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .hairlineBorder(DS.ColorToken.border, cornerRadius: 14)
        .accessibilityElement(children: .combine)
    }
}
