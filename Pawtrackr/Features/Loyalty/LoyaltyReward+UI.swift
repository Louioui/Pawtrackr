//
//  LoyaltyReward+UI.swift
//  Pawtrackr
//
//  Presentation for rewards, shared by the client Loyalty screen, the
//  Payment step and Loyalty settings. Kept out of LoyaltyReward.swift so the
//  domain type stays SwiftUI-free.
//

import SwiftUI

extension LoyaltyReward.Style {
    var tint: Color {
        switch self {
        case .credit:
            DS.ColorToken.success
        case .care:
            DS.ColorToken.info
        case .upgrade:
            DS.ColorToken.warning
        case .vip:
            Color.purple
        }
    }
}

extension LoyaltyReward {
    var tint: Color { style.tint }

    /// The reward's value as its headline: "$5", "25%", or "FREE" for a Free
    /// Bath (its symbol says what is free). Nil for a manual reward, which
    /// shows its symbol alone.
    @MainActor
    var benefitHeadline: String? {
        switch benefit {
        case .manual:
            nil
        case .amountOff(let amount):
            LoyaltyMoney.compact(amount)
        case .percentOff(let percent):
            "\(NSDecimalNumber(decimal: percent).stringValue)%"
        case .freeBath:
            AppLocalization.localized("loyalty2.reward.free_badge", value: "FREE")
        }
    }

    /// One line saying what the reward does at checkout.
    @MainActor
    var benefitSummary: String {
        switch benefit {
        case .manual:
            AppLocalization.localized("loyalty2.reward.benefit.manual", value: "Staff apply this reward by hand")
        case .amountOff(let amount):
            String(format: AppLocalization.localized("loyalty2.reward.benefit.amount_fmt", value: "%@ off the checkout"), LoyaltyMoney.compact(amount))
        case .percentOff(let percent):
            String(format: AppLocalization.localized("loyalty2.reward.benefit.percent_fmt", value: "%@%% off the services"), NSDecimalNumber(decimal: percent).stringValue)
        case .freeBath:
            AppLocalization.localized("loyalty2.reward.benefit.bath", value: "The Bath service, free")
        }
    }
}

enum LoyaltyMoney {
    /// Currency without cents when the amount is whole: "$5", "$12.50".
    @MainActor
    static func compact(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Formatters.currency.locale
        formatter.numberStyle = .currency
        formatter.currencySymbol = Formatters.currency.currencySymbol
        let isWhole = value.roundedMoney(scale: 0) == value
        formatter.minimumFractionDigits = isWhole ? 0 : 2
        formatter.maximumFractionDigits = isWhole ? 0 : 2
        return formatter.string(from: value as NSDecimalNumber) ?? value.moneyString
    }
}

/// The rounded square a reward's symbol sits in, used by every reward list.
struct LoyaltyRewardGlyph: View {
    let reward: LoyaltyReward
    var size: CGFloat = 44
    var isDimmed = false

    var body: some View {
        Image(systemName: reward.systemImage)
            .font(.system(size: size * 0.42, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                (isDimmed ? Color.gray.opacity(0.45) : reward.tint).gradient,
                in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            )
            .accessibilityHidden(true)
    }
}
