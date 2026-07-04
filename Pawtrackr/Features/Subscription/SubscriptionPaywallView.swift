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
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr",
        category: "paywall"
    )

    init(allowsDismiss: Bool = true) {
        self.allowsDismiss = allowsDismiss
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
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 40, height: 40)
                        .background(.thinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .pressScaleStyle(hapticsEnabled: true)
                .accessibilityLabel("Dismiss")
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

            Text("Elevate Pawtrackr")
                .font(.system(.title, design: .rounded))
                .fontWeight(.black)
                .multilineTextAlignment(.center)

            Text("Unlock the loyalty engine, multi-device sync, and advanced insights.")
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
                title: "Automated Loyalty & Rewards",
                detail: "Configurable point rules and a redeemable rewards catalog."
            )
            PaywallFeatureRow(
                icon: "cloud.fill", tint: .blue,
                title: "Multi-Device CloudKit Sync",
                detail: "Your salon data stays unified across all your devices."
            )
            PaywallFeatureRow(
                icon: "chart.pie.fill", tint: .green,
                title: "Advanced Insights & Export",
                detail: "Deeper revenue dashboards and financial exporting."
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
            Text("Auto-renewable. Cancel anytime in the App Store.")
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
                    Text(isProcessing ? "Connecting to the App Store…" : subscribeTitle)
                        .fontWeight(.bold)
                }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background((isProcessing ? Color.gray : Color.accentColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(!canStartPurchase)
            .padding(.horizontal, 24)

            Button("Restore Purchases", action: startRestore)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .disabled(isProcessing)
        }
    }

    private var legalFootnote: some View {
        HStack(spacing: 6) {
            Link("Terms of Use", destination: AppLinks.termsOfUse)
            Text(verbatim: "·").foregroundStyle(.secondary)
            Link("Privacy Policy", destination: AppLinks.privacyPolicy)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.top, 4)
    }

    // MARK: - Copy derived from the live product

    private var subscribeTitle: LocalizedStringKey {
        hasFreeTrial ? "Start 7-Day Free Trial" : "Subscribe"
    }

    private var hasFreeTrial: Bool {
        product?.subscription?.introductoryOffer?.paymentMode == .freeTrial
    }

    /// e.g. "7 days free, then $29.99/month" — all values sourced from StoreKit.
    private var priceHeadline: String {
        switch productLoadState {
        case .loading:
            return String(localized: "subscription.paywall.loading_price",
                          defaultValue: "Loading subscription…")
        case .unavailable:
            return String(localized: "subscription.paywall.unavailable",
                          defaultValue: "Subscription is temporarily unavailable.")
        case .ready:
            guard let product else {
                return String(localized: "subscription.paywall.unavailable",
                              defaultValue: "Subscription is temporarily unavailable.")
            }
            let perMonth = String(
                format: String(localized: "subscription.paywall.price_per_month",
                               defaultValue: "%@ / month"),
                product.displayPrice
            )
            guard hasFreeTrial, let offer = product.subscription?.introductoryOffer else {
                return perMonth
            }
            let trial = Self.periodText(offer.period)
            return String(
                format: String(localized: "subscription.paywall.trial_then_price",
                               defaultValue: "%@ free, then %@"),
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
        case .day:   return "\(value) day\(value == 1 ? "" : "s")"
        case .week:  return "\(value * 7) days"
        case .month: return "\(value) month\(value == 1 ? "" : "s")"
        case .year:  return "\(value) year\(value == 1 ? "" : "s")"
        @unknown default: return "\(value)"
        }
    }

    // MARK: - Actions

    private func loadProduct() async {
        productLoadState = .loading
        errorMessage = nil
        do {
            product = try await Product.products(for: [EntitlementStore.monthlyProductID]).first
            if product == nil {
                productLoadState = .unavailable
                logger.warning("No product returned for \(EntitlementStore.monthlyProductID, privacy: .public) — is the StoreKit config selected in the scheme?")
            } else {
                productLoadState = .ready
            }
        } catch {
            product = nil
            productLoadState = .unavailable
            errorMessage = String(
                localized: "subscription.paywall.load_failed",
                defaultValue: "We could not load the subscription right now. Please try again later."
            )
            logger.error("Failed to load product: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func startPurchase() {
        guard productLoadState == .ready, product != nil else {
            errorMessage = String(
                localized: "subscription.paywall.unavailable_detail",
                defaultValue: "Subscription is temporarily unavailable. Please try again later."
            )
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
                errorMessage = String(
                    localized: "subscription.paywall.restore_none",
                    defaultValue: "No active subscription was found for this Apple ID."
                )
            }
            isProcessing = false
        }
    }
}

// MARK: - Feature row

private struct PaywallFeatureRow: View {
    let icon: String
    let tint: Color
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

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
