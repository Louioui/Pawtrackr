import SwiftData
import SwiftUI

@MainActor
struct RewardsCatalogView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable var client: Client
    @Query(
        filter: #Predicate<LoyaltyRewardTemplate> { $0.isEnabled == true },
        sort: \LoyaltyRewardTemplate.sortOrder,
        order: .forward
    ) private var rewardTemplates: [LoyaltyRewardTemplate]
    @Query(sort: \LoyaltyConfig.createdAt, order: .forward) private var configs: [LoyaltyConfig]

    @State private var redeemingRewardID: LoyaltyReward.ID?
    @State private var errorMessage: String?
    @State private var successMessage: String?

    private var visibleRewards: [LoyaltyReward] {
        guard configs.first?.isRewardsCatalogEnabled ?? true else { return [] }
        let persistent = rewardTemplates.map(\.displayReward)
        return persistent.isEmpty ? LoyaltyReward.builtInCatalog : persistent
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    balanceHeader
                }

                Section("Rewards") {
                    if visibleRewards.isEmpty {
                        ContentUnavailableView(
                            "Rewards Paused",
                            systemImage: "gift",
                            description: Text("Rewards can be re-enabled in Loyalty settings.")
                        )
                    } else {
                        ForEach(visibleRewards) { reward in
                            rewardRow(reward)
                        }
                    }
                }
            }
            .rewardsCatalogListStyle()
            .navigationTitle("Rewards Catalog")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityLabel("Done")
                }
            }
            .safeAreaInset(edge: .bottom) {
                catalogStatus
            }
        }
    }

    private var balanceHeader: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Available Balance")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("Redeem available loyalty rewards")
                    .font(.subheadline.weight(.semibold))
            }

            Spacer()

            LoyaltyPointsBadge(client: client, scale: .compact)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Available balance, \(client.loyaltyPoints) points")
        .accessibilityIdentifier("rewardsCatalog.balance")
    }

    @ViewBuilder
    private var catalogStatus: some View {
        if let message = successMessage {
            statusBanner(message, tint: DS.ColorToken.success, symbol: "checkmark.circle.fill")
        } else if let message = errorMessage {
            statusBanner(message, tint: DS.ColorToken.danger, symbol: "exclamationmark.triangle.fill")
        }
    }

    private func statusBanner(_ message: String, tint: Color, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
            Text(message)
                .font(.footnote.weight(.semibold))
            Spacer(minLength: 0)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal)
        .padding(.bottom, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("rewardsCatalog.status")
    }

    private func rewardRow(_ reward: LoyaltyReward) -> some View {
        let canRedeem = reward.isRedeemable(with: client.loyaltyPoints)
        let isRedeeming = redeemingRewardID == reward.id

        return HStack(spacing: 14) {
            Image(systemName: reward.systemImage)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(reward.style.tint.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(reward.title)
                    .font(.subheadline.weight(.semibold))
                Text(reward.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(reward.pointCost) points")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(reward.style.tint)
            }

            Spacer(minLength: 8)

            Button {
                redeem(reward)
            } label: {
                Group {
                    if isRedeeming {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Text(canRedeem ? "Redeem" : "Locked")
                            .font(.caption.weight(.bold))
                    }
                }
                .frame(width: 72)
                .padding(.vertical, 8)
                .foregroundStyle(canRedeem ? .white : .secondary)
                .background(
                    canRedeem ? reward.style.tint : Color.gray.opacity(0.16),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .disabled(!canRedeem || redeemingRewardID != nil)
            .pressScaleStyle(hapticsEnabled: true)
            .accessibilityLabel("\(canRedeem ? "Redeem" : "Locked"), \(reward.title)")
            .accessibilityIdentifier("rewardsCatalog.reward.\(reward.id).redeem")
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }

    private func redeem(_ reward: LoyaltyReward) {
        guard reward.isRedeemable(with: client.loyaltyPoints) else { return }
        redeemingRewardID = reward.id
        errorMessage = nil
        successMessage = nil

        Task {
            do {
                let service = LoyaltyService(modelContainer: modelContext.container)
                try await service.redeemPoints(client: client, points: reward.pointCost, reason: reward.title)
                withAnimation(MotionSystem.snappy) {
                    successMessage = "Redeemed \(reward.title)"
                }
                HapticManager.notify(.success)
            } catch {
                withAnimation(MotionSystem.snappy) {
                    errorMessage = error.localizedDescription
                }
                HapticManager.notify(.error)
            }
            redeemingRewardID = nil
        }
    }
}

private extension LoyaltyReward.Style {
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

private extension View {
    @ViewBuilder
    func rewardsCatalogListStyle() -> some View {
        #if os(iOS)
        listStyle(.insetGrouped)
        #else
        self
        #endif
    }
}
