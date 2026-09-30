//
//  CheckoutRewardsSection.swift
//  Pawtrackr
//
//  Loyalty 2.0 on the Payment step: the client's rewards as a row of tickets.
//  Tapping a ready one takes it off the bill; the points are spent only when
//  the checkout is confirmed, in the same save as the payment.
//

import SwiftUI

@MainActor
struct CheckoutRewardsSection: View {
    let viewModel: CheckoutViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(viewModel.loyaltyRewards) { reward in
                        ticket(for: reward)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
            }
            .scrollClipDisabled()

            if let applied = viewModel.appliedReward {
                appliedBanner(for: applied)
                    .padding(.horizontal)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(MotionSystem.resolved(MotionSystem.bouncy, reduceMotion: reduceMotion), value: viewModel.appliedReward?.id)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("checkout.rewards")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(AppLocalization.localized("checkout.rewards.title", value: "Loyalty Rewards"))
                    .font(.headline)
                Text(balanceText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            Spacer()
            Image(systemName: "gift.fill")
                .foregroundStyle(DS.ColorToken.warning)
                .accessibilityHidden(true)
        }
    }

    private var balanceText: String {
        let name = viewModel.pet.owner?.firstName ?? ""
        return String(
            format: AppLocalization.localized("checkout.rewards.balance_fmt", value: "%1$@ has %2$@ to spend"),
            name,
            LoyaltyCopy.points(viewModel.clientLoyaltyPoints)
        )
    }

    private func ticket(for reward: LoyaltyReward) -> some View {
        let availability = viewModel.availability(of: reward)
        let isApplied = viewModel.appliedReward?.id == reward.id
        let isReady: Bool = {
            if case .ready = availability { return true }
            return false
        }()

        return Button {
            HapticManager.impact(isApplied ? .light : .medium)
            viewModel.toggleReward(reward)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    LoyaltyRewardGlyph(reward: reward, size: 34, isDimmed: !isReady && !isApplied)
                    Spacer(minLength: 4)
                    Image(systemName: isApplied ? "checkmark.seal.fill" : (isReady ? "plus.circle" : "lock.fill"))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(isApplied ? Color.white : (isReady ? reward.tint : Color.secondary))
                        .symbolEffect(.bounce, value: isApplied)
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 2) {
                    if let headline = reward.benefitHeadline {
                        Text(headline)
                            .font(.system(.title2, design: .rounded).weight(.black))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    Text(LoyaltyCopy.title(for: reward))
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }

                Text(statusText(for: reward, availability, isApplied: isApplied))
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(isApplied ? Color.white.opacity(0.9) : Color.secondary)
            }
            .foregroundStyle(isApplied ? Color.white : Color.primary)
            .padding(12)
            .frame(width: 148, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isApplied ? AnyShapeStyle(reward.tint.gradient) : AnyShapeStyle(DS.ColorToken.surface))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isReady && !isApplied ? reward.tint.opacity(0.55) : Color.clear, lineWidth: 1.5)
            )
            .scaleEffect(isApplied ? 1.04 : 1)
            .opacity(isReady || isApplied ? 1 : 0.6)
        }
        .buttonStyle(.plain)
        .disabled(!isReady && !isApplied)
        .accessibilityLabel(accessibilityLabel(for: reward, availability: availability, isApplied: isApplied))
        .accessibilityAddTraits(isApplied ? .isSelected : [])
        .accessibilityIdentifier("checkout.reward.\(reward.id)")
    }

    private func appliedBanner(for reward: LoyaltyReward) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.headline)
                .foregroundStyle(reward.tint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(String(
                    format: AppLocalization.localized("checkout.rewards.applied_fmt", value: "%1$@ applied: %2$@ off"),
                    LoyaltyCopy.title(for: reward),
                    viewModel.rewardDiscountDecimal.moneyString
                ))
                .font(.subheadline.weight(.semibold))
                .contentTransition(.numericText())
                Text(String(
                    format: AppLocalization.localized("checkout.rewards.spend_on_confirm_fmt", value: "%@ are spent when you confirm."),
                    LoyaltyCopy.points(reward.pointCost)
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button(AppLocalization.localized("checkout.rewards.remove", value: "Remove")) {
                HapticManager.impact(.light)
                viewModel.removeAppliedReward()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("checkout.reward.remove")
        }
        .padding(12)
        .background(reward.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("checkout.rewards.applied")
    }

    private func statusText(for reward: LoyaltyReward, _ availability: CheckoutViewModel.RewardAvailability, isApplied: Bool) -> String {
        switch availability {
        case .ready(let discount):
            let amount = String(format: AppLocalization.localized("checkout.rewards.minus_fmt", value: "−%@"), discount.moneyString)
            if isApplied {
                return String(format: AppLocalization.localized("checkout.rewards.status_applied_fmt", value: "%@ applied"), amount)
            }
            return String(
                format: AppLocalization.localized("checkout.rewards.status_ready_fmt", value: "%1$@ for %2$@"),
                amount,
                LoyaltyCopy.points(reward.pointCost)
            )
        case .needsPoints(let missing):
            return String(format: AppLocalization.localized("checkout.rewards.status_short_fmt", value: "%@ to go"), LoyaltyCopy.points(missing))
        case .notApplicable:
            return AppLocalization.localized("checkout.rewards.status_unavailable", value: "Not for this ticket")
        }
    }

    private func accessibilityLabel(
        for reward: LoyaltyReward,
        availability: CheckoutViewModel.RewardAvailability,
        isApplied: Bool
    ) -> String {
        let title = LoyaltyCopy.title(for: reward)
        switch availability {
        case .ready(let discount):
            let format = isApplied
                ? AppLocalization.localized("checkout.rewards.a11y_applied_fmt", value: "%1$@ applied, %2$@ off. Double-tap to remove.")
                : AppLocalization.localized("checkout.rewards.a11y_ready_fmt", value: "Apply %1$@, %2$@ off.")
            return String(format: format, title, discount.moneyString)
        case .needsPoints(let missing):
            return String(
                format: AppLocalization.localized("checkout.rewards.a11y_locked_fmt", value: "%1$@, locked. %2$@ to go."),
                title,
                LoyaltyCopy.points(missing)
            )
        case .notApplicable:
            return String(
                format: AppLocalization.localized("checkout.rewards.a11y_unavailable_fmt", value: "%@, not available for this ticket."),
                title
            )
        }
    }
}
