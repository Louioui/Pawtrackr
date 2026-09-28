//
//  SubscriptionPaywallView.swift
//  Pawtrackr
//
//  Pawtrackr Pro paywall. Reads the EntitlementStore from the environment and
//  drives StoreKit purchase / restore. Pricing is loaded live from StoreKit
//  (never hardcoded) per ADR-0001.
//

import SwiftUI
import StoreKit
import OSLog

struct SubscriptionPaywallView: View {
    private enum ProductLoadState: Equatable {
        case loading
        case ready
        case unavailable
    }

    @Environment(EntitlementStore.self) private var entitlements
    @Environment(\.dismiss) private var dismiss

    @State private var product: Product?
    @State private var productLoadState: ProductLoadState = .loading
    @State private var isProcessing = false
    @State private var errorMessage: String?

    private let allowsDismiss: Bool
    private let onDismiss: (() -> Void)?
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr",
        category: "paywall"
    )

    init(allowsDismiss: Bool = true, onDismiss: (() -> Void)? = nil) {
        self.allowsDismiss = allowsDismiss
        self.onDismiss = onDismiss
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                header
                featureList
                offerCard
                actions
                legalFootnote
            }
            .padding(.vertical, 32)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .background(DS.ColorToken.background)
        .overlay(alignment: .topTrailing) {
            if allowsDismiss {
                Button {
                    if let onDismiss {
                        onDismiss()
                    } else {
                        dismiss()
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 40, height: 40)
                        .background(.thinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .pressScaleStyle(hapticsEnabled: true)
                .accessibilityLabel(AppLocalization.localized("common.dismiss", value: "Dismiss"))
                .accessibilityIdentifier("subscriptionPaywall.dismiss")
                .padding(.top, 12)
                .padding(.trailing, 16)
            }
        }
        .task { await loadProduct() }
        // If the entitlement resolves to active (e.g. purchase/restore succeeds,
        // or a family-shared entitlement arrives), close automatically.
        .onChange(of: entitlements.isPremium) { _, isPremium in
            if isPremium { dismiss() }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "crown.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.orange.gradient)
                .shadow(color: .orange.opacity(0.3), radius: 10, y: 5)

            Text(AppLocalization.localized("subscription.paywall.headline", value: "Elevate Pawtrackr"))
                .font(.system(.title, design: .rounded))
                .fontWeight(.black)
                .multilineTextAlignment(.center)

            Text(AppLocalization.localized("subscription.paywall.subheadline", value: "Unlock the loyalty engine, multi-device sync, and advanced insights."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .padding(.top, 16)
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 16) {
            PaywallFeatureRow(
                icon: "heart.text.square.fill", tint: .pink,
                title: AppLocalization.localized("subscription.paywall.feature.loyalty_title", value: "Automated Loyalty & Rewards"),
                detail: AppLocalization.localized("subscription.paywall.feature.loyalty_detail", value: "Configurable point rules and a redeemable rewards catalog.")
            )
            PaywallFeatureRow(
                icon: "cloud.fill", tint: .blue,
                title: AppLocalization.localized("subscription.paywall.feature.sync_title", value: "Multi-Device iCloud Sync"),
                detail: AppLocalization.localized("subscription.paywall.feature.sync_detail", value: "Your salon data stays unified across all your devices.")
            )
            PaywallFeatureRow(
                icon: "chart.pie.fill", tint: .green,
                title: AppLocalization.localized("subscription.paywall.feature.insights_title", value: "Advanced Insights & Export"),
                detail: AppLocalization.localized("subscription.paywall.feature.insights_detail", value: "Deeper revenue dashboards and financial exporting.")
            )
        }
        .padding(.horizontal, 24)
    }

    private var offerCard: some View {
        VStack(spacing: 6) {
            Text(priceHeadline)
                .font(.headline)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            Text(AppLocalization.localized("subscription.paywall.renewal_note", value: "Auto-renewable. Cancel anytime in the App Store."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(DS.ColorToken.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.orange.opacity(0.4), lineWidth: 2)
        )
        .padding(.horizontal, 24)
    }

    private var actions: some View {
        VStack(spacing: 12) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Button(action: startPurchase) {
                HStack(spacing: 8) {
                    if isProcessing { ProgressView().tint(.white) }
                    Text(isProcessing ? AppLocalization.localized("subscription.paywall.connecting", value: "Connecting to the App Store…") : subscribeTitle)
                        .fontWeight(.bold)
                }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background((isProcessing ? Color.gray : Color.accentColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(!canStartPurchase)
            // A full-color button that silently ignores taps reads as broken;
            // dim it whenever a purchase can't actually start.
            .opacity(canStartPurchase || isProcessing ? 1 : 0.5)
            .motionAnimation(MotionSystem.fastEaseOut, value: canStartPurchase || isProcessing)
            .padding(.horizontal, 24)
            .accessibilityIdentifier("subscriptionPaywall.subscribe")

            if productLoadState == .unavailable {
                Button {
                    Task { await loadProduct() }
                } label: {
                    Label(
                        AppLocalization.localized("subscription.paywall.retry", value: "Try Again"),
                        systemImage: "arrow.clockwise"
                    )
                    .font(.subheadline.weight(.semibold))
                }
                .disabled(isProcessing)
                .buttonStyle(.plain)
                .pressScaleStyle(hapticsEnabled: true)
                .accessibilityIdentifier("subscriptionPaywall.retry")
            }

            Button(AppLocalization.localized("subscription.paywall.restore", value: "Restore Purchases"), action: startRestore)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .disabled(isProcessing)
        }
    }

    private var legalFootnote: some View {
        HStack(spacing: 6) {
            Link(AppLocalization.localized("subscription.paywall.terms", value: "Terms of Use"), destination: AppLinks.termsOfUse)
            Text(verbatim: "·").foregroundStyle(.secondary)
            Link(AppLocalization.localized("subscription.paywall.privacy", value: "Privacy Policy"), destination: AppLinks.privacyPolicy)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.top, 4)
    }

    // MARK: - Copy derived from the live product

    private var subscribeTitle: String {
        hasFreeTrial
            ? AppLocalization.localized("subscription.paywall.start_trial", value: "Start 7-Day Free Trial")
            : AppLocalization.localized("subscription.paywall.subscribe", value: "Subscribe")
    }

    private var hasFreeTrial: Bool {
        product?.subscription?.introductoryOffer?.paymentMode == .freeTrial
    }

    /// e.g. "7 days free, then $29.99/month" — all values sourced from StoreKit.
    private var priceHeadline: String {
        switch productLoadState {
        case .loading:
            return AppLocalization.localized("subscription.paywall.loading_price", value: "Loading subscription…")
        case .unavailable:
            return AppLocalization.localized("subscription.paywall.unavailable", value: "Subscription is temporarily unavailable.")
        case .ready:
            guard let product else {
                return AppLocalization.localized("subscription.paywall.unavailable", value: "Subscription is temporarily unavailable.")
            }
            let perMonth = String(
                format: AppLocalization.localized("subscription.paywall.price_per_month", value: "%@ / month"),
                product.displayPrice
            )
            guard hasFreeTrial, let offer = product.subscription?.introductoryOffer else {
                return perMonth
            }
            let trial = Self.periodText(offer.period)
            return String(
                format: AppLocalization.localized("subscription.paywall.trial_then_price", value: "%@ free, then %@"),
                trial, perMonth
            )
        }
    }

    private var canStartPurchase: Bool {
        productLoadState == .ready && product != nil && !isProcessing
    }

    private static func periodText(_ period: Product.SubscriptionPeriod) -> String {
        let value = period.value
        switch period.unit {
        case .day:   return dayText(value)
        case .week:  return dayText(value * 7)
        case .month:
            return value == 1
                ? AppLocalization.localized("subscription.period.month_one", value: "1 month")
                : String(format: AppLocalization.localized("subscription.period.months_fmt", value: "%d months"), value)
        case .year:
            return value == 1
                ? AppLocalization.localized("subscription.period.year_one", value: "1 year")
                : String(format: AppLocalization.localized("subscription.period.years_fmt", value: "%d years"), value)
        @unknown default: return "\(value)"
        }
    }

    private static func dayText(_ days: Int) -> String {
        days == 1
            ? AppLocalization.localized("subscription.period.day_one", value: "1 day")
            : String(format: AppLocalization.localized("subscription.period.days_fmt", value: "%d days"), days)
    }

    // MARK: - Actions

    private func loadProduct() async {
        productLoadState = .loading
        errorMessage = nil
        do {
            // Bounded fetch: a hung StoreKit call must surface the retry state,
            // never an infinite "Loading subscription…" spinner.
            product = try await StoreKitTimeout.run {
                try await Product.products(for: [EntitlementStore.monthlyProductID]).first
            }
            if product == nil {
                productLoadState = .unavailable
                logger.warning("No product returned for \(EntitlementStore.monthlyProductID, privacy: .public) — is the StoreKit config selected in the scheme?")
            } else {
                productLoadState = .ready
            }
        } catch {
            product = nil
            productLoadState = .unavailable
            errorMessage = AppLocalization.localized("subscription.paywall.load_failed", value: "We could not load the subscription right now. Please try again later.")
            logger.error("Failed to load product: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func startPurchase() {
        guard productLoadState == .ready, product != nil else {
            errorMessage = AppLocalization.localized("subscription.paywall.unavailable_detail", value: "Subscription is temporarily unavailable. Please try again later.")
            return
        }
        isProcessing = true
        errorMessage = nil
        Task {
            do {
                _ = try await entitlements.purchaseMonthly()
                // onChange(of: isPremium) dismisses on success; surface a message
                // only if the user is still not entitled and didn't cancel.
            } catch {
                errorMessage = error.localizedDescription
            }
            isProcessing = false
        }
    }

    private func startRestore() {
        isProcessing = true
        errorMessage = nil
        Task {
            await entitlements.restore()
            if !entitlements.isPremium {
                errorMessage = AppLocalization.localized("subscription.paywall.restore_none", value: "No active subscription was found for this Apple ID.")
            }
            isProcessing = false
        }
    }
}

// MARK: - Feature row

private struct PaywallFeatureRow: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).fontWeight(.semibold)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}
