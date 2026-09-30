//
//  ClientLoyaltyView.swift
//  Pawtrackr
//
//  Loyalty 2.0: a client's points pass, the reward track, the rewards they
//  can spend, and their points activity.
//

import SwiftData
import SwiftUI

@MainActor
struct ClientLoyaltyView: View {
    private enum SheetDestination: Identifiable {
        case adjustment
        case redeem(LoyaltyReward)

        var id: String {
            switch self {
            case .adjustment:
                "adjustment"
            case .redeem(let reward):
                "redeem.\(reward.id)"
            }
        }
    }

    /// Activity rows shown before "Show all".
    private static let activityPreviewCount = 6

    @Bindable var client: Client
    @Query private var ledgerEntries: [LoyaltyLedgerEntry]
    @Query(sort: \LoyaltyRewardTemplate.sortOrder, order: .forward) private var rewardTemplates: [LoyaltyRewardTemplate]
    @Query(sort: \LoyaltyConfig.createdAt, order: .forward) private var configs: [LoyaltyConfig]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var sheetDestination: SheetDestination?
    @State private var animatedTierProgress: Double = 0
    @State private var showsAllActivity = false
    @State private var redeemedRewardID: LoyaltyReward.ID?
    @State private var statusMessage: String?

    init(client: Client) {
        self.client = client
        let clientUUID = client.uuid
        _ledgerEntries = Query(
            filter: #Predicate<LoyaltyLedgerEntry> { $0.clientUUID == clientUUID },
            sort: [SortDescriptor(\LoyaltyLedgerEntry.createdAt, order: .reverse)]
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                pointsPass
                rewardsSection
                statsStrip
                tierCard
                activitySection
            }
            .padding(.vertical, 12)
            .frame(maxWidth: 780)
            .frame(maxWidth: .infinity)
        }
        .background(DS.ColorToken.background)
        .navigationTitle(AppLocalization.localized("client_detail.loyalty.title", value: "Loyalty & Rewards"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .safeAreaInset(edge: .bottom) {
            if let statusMessage {
                statusToast(statusMessage)
            }
        }
        .sheet(item: $sheetDestination) { destination in
            switch destination {
            case .adjustment:
                LoyaltyAdjustmentSheet(client: client)
            case .redeem(let reward):
                LoyaltyRedeemSheet(client: client, reward: reward) { redeemed in
                    celebrateRedemption(of: redeemed)
                }
            }
        }
    }

    // MARK: - Points pass

    private var pointsPass: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(client.fullName)
                        .font(.headline)
                    Label(
                        String(format: AppLocalization.localized("loyalty.client.member_fmt", value: "%1$@ member • %2$@ earn rate"), tier.displayName, tier.earnRateText),
                        systemImage: tier.systemImage
                    )
                    .font(.caption.weight(.semibold))
                    .padding(.vertical, 4)
                    .padding(.horizontal, 9)
                    .background(.white.opacity(0.2), in: Capsule())
                }

                Spacer(minLength: 12)

                Button {
                    sheetDestination = .adjustment
                } label: {
                    Label(AppLocalization.localized("loyalty2.pass.adjust", value: "Adjust"), systemImage: "slider.horizontal.3")
                        .font(.caption.weight(.bold))
                        .padding(.vertical, 7)
                        .padding(.horizontal, 11)
                        .background(.white.opacity(0.2), in: Capsule())
                }
                .buttonStyle(.plain)
                .pressScaleStyle(hapticsEnabled: true)
                .accessibilityLabel(AppLocalization.localized("loyalty.client.adjust_accessibility", value: "Adjust loyalty points"))
                .accessibilityIdentifier("clientLoyalty.adjustPoints")
            }

            VStack(alignment: .leading, spacing: 0) {
                Text("\(client.loyaltyPoints)")
                    .font(.system(size: 60, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(client.loyaltyPoints)))
                    .animation(MotionSystem.resolved(MotionSystem.bouncy, reduceMotion: reduceMotion), value: client.loyaltyPoints)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(AppLocalization.localized("loyalty2.pass.points_label", value: "points to spend"))
                    .font(.subheadline.weight(.semibold))
                    .opacity(0.85)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(String(
                format: AppLocalization.localized("loyalty.client.balance_accessibility_fmt", value: "%1$@, %2$d loyalty points, %3$@ tier"),
                client.fullName,
                client.loyaltyPoints,
                tier.displayName
            ))
            .accessibilityIdentifier("clientLoyalty.balance")

            if !rewardsByCost.isEmpty {
                LoyaltyRewardTrack(rewards: rewardsByCost, balance: client.loyaltyPoints)
                    .accessibilityIdentifier("clientLoyalty.rewardTrack")
            }

            Text(passCaption)
                .font(.footnote.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("clientLoyalty.nextReward")
        }
        .foregroundStyle(.white)
        .padding(20)
        .background(passBackground)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: tier.tint.opacity(0.35), radius: 18, y: 10)
        .padding(.horizontal)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clientLoyalty.pass")
    }

    private var passBackground: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(
                colors: [tier.tint, tier.tint.mix(with: .black, by: 0.35)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "pawprint.fill")
                .font(.system(size: 150, weight: .black))
                .foregroundStyle(.white.opacity(0.08))
                .rotationEffect(.degrees(-18))
                .offset(x: 34, y: -18)
                .accessibilityHidden(true)
        }
    }

    private var passCaption: String {
        if rewardCatalog.isEmpty {
            return AppLocalization.localized("loyalty.client.rewards_paused_settings", value: "Rewards are paused in Loyalty settings")
        }
        if let nextReward {
            let remaining = nextReward.pointsNeeded(from: client.loyaltyPoints)
            let title = LoyaltyCopy.title(for: nextReward)
            if let visits = projectedVisits(toEarn: remaining) {
                return visits == 1
                    ? String(format: AppLocalization.localized("loyalty2.pass.next_one_visit_fmt", value: "%1$@ to %2$@, about 1 visit away."), LoyaltyCopy.points(remaining), title)
                    : String(format: AppLocalization.localized("loyalty2.pass.next_visits_fmt", value: "%1$@ to %2$@, about %3$d visits away."), LoyaltyCopy.points(remaining), title, visits)
            }
            return String(format: AppLocalization.localized("loyalty2.pass.next_fmt", value: "%1$@ to %2$@."), LoyaltyCopy.points(remaining), title)
        }
        return AppLocalization.localized("loyalty.client.all_unlocked", value: "Every active reward is unlocked")
    }

    // MARK: - Rewards

    private var rewardsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(AppLocalization.localized("loyalty2.rewards.title", value: "Rewards"))
                        .font(.title3.weight(.bold))
                    Spacer()
                    if !redeemableRewards.isEmpty {
                        Text(String(format: AppLocalization.localized("loyalty2.rewards.ready_count_fmt", value: "%d ready"), redeemableRewards.count))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 9)
                            .background(DS.ColorToken.success, in: Capsule())
                            .contentTransition(.numericText())
                    }
                }
                Text(AppLocalization.localized("loyalty2.rewards.subtitle", value: "Apply a reward on the Payment step to take it off the bill, or redeem it here."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal)

            if rewardCatalog.isEmpty {
                ContentUnavailableView(
                    AppLocalization.localized("loyalty.catalog.paused_title", value: "Rewards Paused"),
                    systemImage: "gift",
                    description: Text(AppLocalization.localized("loyalty.catalog.paused_detail", value: "Rewards can be re-enabled in Loyalty settings."))
                )
                .padding(.vertical, 12)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                    ForEach(rewardsByCost) { reward in
                        LoyaltyRewardCard(
                            reward: reward,
                            balance: client.loyaltyPoints,
                            isCelebrating: redeemedRewardID == reward.id
                        ) {
                            sheetDestination = .redeem(reward)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Stats

    private var statsStrip: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 10)], spacing: 10) {
            LoyaltySmartStatCard(
                title: AppLocalization.localized("loyalty2.stat.lifetime", value: "Lifetime Earned"),
                value: "\(lifetimeEarned)",
                detail: AppLocalization.localized("loyalty2.stat.lifetime_detail", value: "Points from visits"),
                systemImage: "star.fill",
                tint: tier.tint
            )

            LoyaltySmartStatCard(
                title: AppLocalization.localized("loyalty.client.stat.change_30", value: "30-Day Change"),
                value: signedPointsText(pointsDelta30Days),
                detail: pointsDelta30Days >= 0
                    ? AppLocalization.localized("loyalty.client.stat.net_gained", value: "Net points gained")
                    : AppLocalization.localized("loyalty.client.stat.net_spent", value: "Net points spent"),
                systemImage: pointsDelta30Days >= 0 ? "chart.line.uptrend.xyaxis" : "arrow.down.circle.fill",
                tint: pointsDelta30Days >= 0 ? DS.ColorToken.success : DS.ColorToken.danger
            )

            LoyaltySmartStatCard(
                title: AppLocalization.localized("loyalty.client.stat.avg_earn", value: "Avg Earn"),
                value: averageEarnedPerVisit > 0 ? "\(averageEarnedPerVisit)" : "—",
                detail: averageEarnedPerVisit > 0
                    ? AppLocalization.localized("loyalty.client.stat.points_per_visit", value: "Points per visit")
                    : AppLocalization.localized("loyalty.client.stat.no_visits", value: "No visits yet"),
                systemImage: "pawprint.fill",
                tint: DS.ColorToken.info
            )
        }
        .padding(.horizontal)
    }

    // MARK: - Tier

    private var tierCard: some View {
        Card(
            cornerRadius: 18,
            padding: EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18)
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: tier.systemImage)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(tier.tint.gradient, in: Circle())

                    VStack(alignment: .leading, spacing: 1) {
                        Text(String(format: AppLocalization.localized("loyalty.client.tier_title_fmt", value: "%@ Tier"), tier.displayName))
                            .font(.subheadline.weight(.bold))
                        Text(String(format: AppLocalization.localized("loyalty.client.tier_earn_fmt", value: "Every visit earns %@ points"), tier.earnRateText))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)
                }

                ProgressView(value: animatedTierProgress)
                    .tint(tier.next?.tint ?? tier.tint)
                Text(tierProgressText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                tierLadder
            }
        }
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tierAccessibilityLabel)
        .accessibilityIdentifier("clientLoyalty.tierCard")
        .task {
            withAnimation(MotionSystem.resolved(MotionSystem.fluid.delay(0.15), reduceMotion: reduceMotion)) {
                animatedTierProgress = LoyaltyEngine.tierProgress(lifetimeEarned: lifetimeEarned)
            }
        }
        .onChange(of: lifetimeEarned) { _, newValue in
            withAnimation(MotionSystem.resolved(MotionSystem.fluid, reduceMotion: reduceMotion)) {
                animatedTierProgress = LoyaltyEngine.tierProgress(lifetimeEarned: newValue)
            }
        }
    }

    private var tierLadder: some View {
        HStack(spacing: 8) {
            ForEach(LoyaltyTier.allCases, id: \.self) { ladderTier in
                let isUnlocked = lifetimeEarned >= ladderTier.threshold
                let accessibilityDetail = isUnlocked
                    ? AppLocalization.localized("loyalty.client.ladder_unlocked", value: "unlocked")
                    : String(format: AppLocalization.localized("loyalty.client.points_away_fmt", value: "%d points away"), max(0, ladderTier.threshold - lifetimeEarned))
                HStack(spacing: 6) {
                    Image(systemName: ladderTier.systemImage)
                        .font(.caption2.weight(.bold))
                    Text(ladderTier.displayName)
                        .font(.caption2.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .foregroundStyle(isUnlocked ? .white : ladderTier.tint)
                .padding(.vertical, 5)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity)
                .background(isUnlocked ? ladderTier.tint : ladderTier.tint.opacity(0.12), in: Capsule())
                .accessibilityLabel(String(format: AppLocalization.localized("loyalty.client.ladder_accessibility_fmt", value: "%1$@ tier, %2$@"), ladderTier.displayName, accessibilityDetail))
            }
        }
    }

    // MARK: - Activity

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(AppLocalization.localized("loyalty2.activity.title", value: "Points Activity"))
                    .font(.title3.weight(.bold))
                Spacer()
                Text("\(ledgerEntries.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 3)
                    .padding(.horizontal, 7)
                    .background(Capsule().fill(Color.gray.opacity(0.14)))
            }
            .padding(.horizontal)

            if ledgerEntries.isEmpty {
                ContentUnavailableView(
                    AppLocalization.localized("loyalty.client.ledger_empty_title", value: "No Loyalty History"),
                    systemImage: "clock.arrow.2.circlepath",
                    description: Text(AppLocalization.localized("loyalty.client.ledger_empty_detail", value: "Earned points, redemptions, and adjustments will appear here."))
                )
                .padding(.vertical, 28)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(visibleActivity) { entry in
                        LoyaltyLedgerEntryRow(entry: entry)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.horizontal)

                if ledgerEntries.count > Self.activityPreviewCount {
                    Button {
                        withAnimation(MotionSystem.resolved(MotionSystem.fluid, reduceMotion: reduceMotion)) {
                            showsAllActivity.toggle()
                        }
                    } label: {
                        Text(showsAllActivity
                             ? AppLocalization.localized("loyalty2.activity.show_less", value: "Show less")
                             : String(format: AppLocalization.localized("loyalty2.activity.show_all_fmt", value: "Show all %d"), ledgerEntries.count))
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .padding(.horizontal)
                    .accessibilityIdentifier("clientLoyalty.activity.toggle")
                }
            }
        }
        .padding(.bottom, 24)
    }

    private var visibleActivity: [LoyaltyLedgerEntry] {
        showsAllActivity ? ledgerEntries : Array(ledgerEntries.prefix(Self.activityPreviewCount))
    }

    // MARK: - Redemption feedback

    private func celebrateRedemption(of reward: LoyaltyReward) {
        let animation = MotionSystem.resolved(MotionSystem.bouncy, reduceMotion: reduceMotion)
        withAnimation(animation) {
            redeemedRewardID = reward.id
            statusMessage = String(
                format: AppLocalization.localized("loyalty.catalog.redeemed_fmt", value: "Redeemed %@"),
                LoyaltyCopy.title(for: reward)
            )
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.4))
            withAnimation(animation) {
                redeemedRewardID = nil
                statusMessage = nil
            }
        }
    }

    private func statusToast(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
            Text(message)
                .font(.footnote.weight(.semibold))
            Spacer(minLength: 0)
        }
        .foregroundStyle(DS.ColorToken.success)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal)
        .padding(.bottom, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("clientLoyalty.status")
    }

    // MARK: - Derived state

    private var tier: LoyaltyTier {
        LoyaltyEngine.tier(forLifetimeEarned: lifetimeEarned)
    }

    private var lifetimeEarned: Int {
        LoyaltyEngine.lifetimeEarnedPoints(for: client)
    }

    private var tierProgressText: String {
        if let next = tier.next, let remaining = LoyaltyEngine.pointsUntilNextTier(lifetimeEarned: lifetimeEarned) {
            return String(format: AppLocalization.localized("loyalty.client.tier_progress_fmt", value: "%1$d earned points until %2$@ (%3$@ earn rate)"), remaining, next.displayName, next.earnRateText)
        }
        return String(format: AppLocalization.localized("loyalty.client.top_tier_fmt", value: "Top tier reached. Every visit earns %@ points."), tier.earnRateText)
    }

    private var tierAccessibilityLabel: String {
        if let next = tier.next, let remaining = LoyaltyEngine.pointsUntilNextTier(lifetimeEarned: lifetimeEarned) {
            return String(format: AppLocalization.localized("loyalty.client.tier_accessibility_fmt", value: "%1$@ tier, %2$d points until %3$@"), tier.displayName, remaining, next.displayName)
        }
        return String(format: AppLocalization.localized("loyalty.client.top_tier_accessibility_fmt", value: "%@ tier, top tier"), tier.displayName)
    }

    private var rewardCatalog: [LoyaltyReward] {
        LoyaltyRewardCatalog.active(
            templates: rewardTemplates,
            config: LoyaltyConfigResolver.snapshot(from: configs)
        )
    }

    private var rewardsByCost: [LoyaltyReward] {
        LoyaltyRewardCatalog.byCost(rewardCatalog)
    }

    private var redeemableRewards: [LoyaltyReward] {
        rewardsByCost.filter { $0.isRedeemable(with: client.loyaltyPoints) }
    }

    private var nextReward: LoyaltyReward? {
        rewardsByCost.first { $0.pointCost > client.loyaltyPoints }
    }

    private var pointsDelta30Days: Int {
        let startDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? .distantPast
        return ledgerEntries
            .filter { $0.createdAt >= startDate }
            .reduce(0) { $0 + $1.points }
    }

    private var averageEarnedPerVisit: Int {
        let earnedEntries = ledgerEntries.filter { $0.kind == .earned && $0.points > 0 }
        guard !earnedEntries.isEmpty else { return 0 }
        let total = earnedEntries.reduce(0) { $0 + $1.points }
        return max(1, total / earnedEntries.count)
    }

    private func projectedVisits(toEarn remaining: Int) -> Int? {
        guard remaining > 0, averageEarnedPerVisit > 0 else { return nil }
        return (remaining + averageEarnedPerVisit - 1) / averageEarnedPerVisit
    }

    private func signedPointsText(_ value: Int) -> String {
        value > 0 ? "+\(value)" : "\(value)"
    }
}

// MARK: - Reward track

/// The pass's progress line: the balance fills toward the most expensive
/// reward, and each reward sits on the line at its cost, lighting up once the
/// balance reaches it.
private struct LoyaltyRewardTrack: View {
    let rewards: [LoyaltyReward]
    let balance: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animatedFraction: Double = 0

    private static let nodeSize: CGFloat = 28

    private var maxCost: Int {
        max(1, rewards.map(\.pointCost).max() ?? 1)
    }

    private var targetFraction: Double {
        min(1, Double(balance) / Double(maxCost))
    }

    var body: some View {
        GeometryReader { proxy in
            let usable = max(0, proxy.size.width - Self.nodeSize)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.22))
                    .frame(height: 8)
                    .padding(.horizontal, Self.nodeSize / 2)

                Capsule()
                    .fill(.white)
                    .frame(width: usable * animatedFraction, height: 8)
                    .padding(.leading, Self.nodeSize / 2)

                ForEach(rewards) { reward in
                    let isUnlocked = reward.isRedeemable(with: balance)
                    Image(systemName: isUnlocked ? reward.systemImage : "lock.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(isUnlocked ? reward.tint : .white.opacity(0.8))
                        .frame(width: Self.nodeSize, height: Self.nodeSize)
                        .background(isUnlocked ? Color.white : Color.white.opacity(0.18), in: Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(isUnlocked ? 0 : 0.5), lineWidth: 1))
                        .scaleEffect(isUnlocked ? 1 : 0.82)
                        .offset(x: usable * Double(reward.pointCost) / Double(maxCost))
                        .animation(MotionSystem.resolved(MotionSystem.bouncy, reduceMotion: reduceMotion), value: isUnlocked)
                }
            }
            .frame(height: Self.nodeSize)
        }
        .frame(height: Self.nodeSize)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .onAppear {
            withAnimation(MotionSystem.resolved(MotionSystem.fluid.delay(0.1), reduceMotion: reduceMotion)) {
                animatedFraction = targetFraction
            }
        }
        .onChange(of: balance) { _, _ in
            withAnimation(MotionSystem.resolved(MotionSystem.fluid, reduceMotion: reduceMotion)) {
                animatedFraction = targetFraction
            }
        }
    }

    private var accessibilitySummary: String {
        let unlocked = rewards.filter { $0.isRedeemable(with: balance) }.count
        return String(
            format: AppLocalization.localized("loyalty2.track.a11y_fmt", value: "%1$d of %2$d rewards unlocked"),
            unlocked,
            rewards.count
        )
    }
}

// MARK: - Reward card

/// One reward in the grid: its value up front, then either "Ready" or a ring
/// showing how close the client is.
private struct LoyaltyRewardCard: View {
    let reward: LoyaltyReward
    let balance: Int
    let isCelebrating: Bool
    let onRedeem: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isReady: Bool { reward.isRedeemable(with: balance) }

    private var progress: Double {
        min(1, Double(balance) / Double(max(1, reward.pointCost)))
    }

    var body: some View {
        Button(action: onRedeem) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    LoyaltyRewardGlyph(reward: reward, size: 40, isDimmed: !isReady)
                    Spacer(minLength: 6)
                    statusBadge
                }

                VStack(alignment: .leading, spacing: 3) {
                    if let headline = reward.benefitHeadline {
                        Text(headline)
                            .font(.system(.largeTitle, design: .rounded).weight(.black))
                            .foregroundStyle(isReady ? reward.tint : Color.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    Text(LoyaltyCopy.title(for: reward))
                        .font(.subheadline.weight(.bold))
                        .lineLimit(2)
                    Text(reward.benefitSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Text(LoyaltyCopy.points(reward.pointCost))
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(isReady ? .white : .secondary)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 10)
                    .background(isReady ? AnyShapeStyle(reward.tint) : AnyShapeStyle(Color.gray.opacity(0.14)), in: Capsule())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(DS.ColorToken.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(isReady ? reward.tint.opacity(0.6) : DS.ColorToken.border, lineWidth: isReady ? 1.5 : 1)
            )
            .overlay(alignment: .center) {
                if isCelebrating {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 64, weight: .bold))
                        .foregroundStyle(reward.tint)
                        .shadow(color: reward.tint.opacity(0.4), radius: 10)
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                        .accessibilityHidden(true)
                }
            }
            .scaleEffect(isCelebrating ? 0.96 : 1)
            .shadow(color: isReady ? reward.tint.opacity(0.18) : .clear, radius: 10, y: 5)
        }
        .buttonStyle(.plain)
        .pressScaleStyle(hapticsEnabled: true)
        .disabled(!isReady)
        .animation(MotionSystem.resolved(MotionSystem.bouncy, reduceMotion: reduceMotion), value: isReady)
        .animation(MotionSystem.resolved(MotionSystem.bouncy, reduceMotion: reduceMotion), value: isCelebrating)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(isReady ? AppLocalization.localized("loyalty2.card.a11y_hint", value: "Opens redemption") : "")
        .accessibilityIdentifier("clientLoyalty.reward.\(reward.id)")
    }

    @ViewBuilder
    private var statusBadge: some View {
        if isReady {
            Text(AppLocalization.localized("loyalty2.card.ready", value: "Ready"))
                .font(.caption2.weight(.heavy))
                .textCase(.uppercase)
                .foregroundStyle(.white)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(DS.ColorToken.success, in: Capsule())
        } else {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.18), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(reward.tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int((progress * 100).rounded(.down)))%")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .frame(width: 36, height: 36)
            .accessibilityHidden(true)
        }
    }

    private var accessibilityLabel: String {
        let title = LoyaltyCopy.title(for: reward)
        if isReady {
            return String(
                format: AppLocalization.localized("loyalty2.card.a11y_ready_fmt", value: "%1$@, ready. %2$@. Costs %3$@."),
                title,
                reward.benefitSummary,
                LoyaltyCopy.points(reward.pointCost)
            )
        }
        return String(
            format: AppLocalization.localized("loyalty2.card.a11y_locked_fmt", value: "%1$@, locked. %2$@ to go."),
            title,
            LoyaltyCopy.points(reward.pointsNeeded(from: balance))
        )
    }
}

// MARK: - Redeem sheet

/// Confirms spending points on a reward outside checkout. Says plainly that
/// this only spends the points: the discount itself is applied at checkout.
@MainActor
private struct LoyaltyRedeemSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable var client: Client
    let reward: LoyaltyReward
    let onRedeemed: (LoyaltyReward) -> Void

    @State private var isRedeeming = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 10) {
                        LoyaltyRewardGlyph(reward: reward, size: 72)
                        if let headline = reward.benefitHeadline {
                            Text(headline)
                                .font(.system(size: 44, weight: .black, design: .rounded))
                                .foregroundStyle(reward.tint)
                        }
                        Text(LoyaltyCopy.title(for: reward))
                            .font(.title3.weight(.bold))
                        Text(reward.benefitSummary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)

                    HStack(spacing: 12) {
                        balanceColumn(
                            title: AppLocalization.localized("loyalty2.redeem.now", value: "Now"),
                            points: client.loyaltyPoints
                        )
                        Image(systemName: "arrow.right")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        balanceColumn(
                            title: AppLocalization.localized("loyalty2.redeem.after", value: "After"),
                            points: max(0, client.loyaltyPoints - reward.pointCost)
                        )
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .background(DS.ColorToken.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    Label(
                        reward.benefit.appliesAtCheckout
                            ? AppLocalization.localized("loyalty2.redeem.checkout_note", value: "To take it off today's bill, apply it on the Payment step at checkout instead. Redeeming here only spends the points.")
                            : AppLocalization.localized("loyalty2.redeem.manual_note", value: "Give the client this reward yourself. Redeeming records it and spends the points."),
                        systemImage: "info.circle"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(DS.ColorToken.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        redeem()
                    } label: {
                        Group {
                            if isRedeeming {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text(String(
                                    format: AppLocalization.localized("loyalty2.redeem.confirm_fmt", value: "Redeem for %@"),
                                    LoyaltyCopy.points(reward.pointCost)
                                ))
                                .font(.headline)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .foregroundStyle(.white)
                        .background(reward.tint.gradient, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .pressScaleStyle(hapticsEnabled: true)
                    .disabled(isRedeeming || !reward.isRedeemable(with: client.loyaltyPoints))
                    .accessibilityIdentifier("rewardRedeem.confirm")
                }
                .padding(20)
            }
            .navigationTitle(AppLocalization.localized("loyalty2.redeem.title", value: "Redeem Reward"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.localized("common.cancel", value: "Cancel")) { dismiss() }
                        .disabled(isRedeeming)
                        .accessibilityIdentifier("rewardRedeem.cancel")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func balanceColumn(title: String, points: Int) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("\(points)")
                .font(.system(.title, design: .rounded).weight(.black))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func redeem() {
        guard reward.isRedeemable(with: client.loyaltyPoints) else { return }
        isRedeeming = true
        errorMessage = nil

        Task {
            do {
                let service = LoyaltyService(modelContainer: modelContext.container)
                try await service.redeemPoints(clientUUID: client.uuid, points: reward.pointCost, reason: LoyaltyCopy.title(for: reward))
                HapticManager.notify(.success)
                onRedeemed(reward)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                HapticManager.notify(.error)
            }
            isRedeeming = false
        }
    }
}

private struct LoyaltySmartStatCard: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Card(
            cornerRadius: 14,
            padding: EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12),
            elevation: .flat
        ) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(tint.gradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(value)
                        .font(.title3.weight(.black))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct LoyaltyLedgerEntryRow: View {
    let entry: LoyaltyLedgerEntry

    var body: some View {
        Card(cornerRadius: 14, padding: EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12), elevation: .regular) {
            HStack(spacing: 12) {
                Image(systemName: kindSymbol)
                    .font(.title3)
                    .foregroundStyle(pointsTint)
                    .frame(width: 34, height: 34)
                    .background(pointsTint.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    HStack(spacing: 6) {
                        Text(Formatters.dateOnly.string(from: entry.createdAt))
                        if let balance = entry.balanceAfter {
                            Text("•")
                            Text(String(format: AppLocalization.localized("loyalty.ledger.balance_fmt", value: "Balance %d"), balance))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Text(pointsText)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(pointsTint)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        switch entry.kind {
        case .earned:
            entry.reason.map { String(format: AppLocalization.localized("loyalty.ledger.visit_fmt", value: "Visit — %@"), $0) }
                ?? AppLocalization.localized("loyalty.ledger.visit_checkout", value: "Visit checkout")
        case .redeemed:
            entry.reason ?? AppLocalization.localized("loyalty.ledger.redeemed", value: "Reward redeemed")
        case .adjusted:
            entry.reason ?? AppLocalization.localized("loyalty.ledger.adjusted", value: "Manual adjustment")
        }
    }

    private var kindSymbol: String {
        switch entry.kind {
        case .earned:
            "plus.circle.fill"
        case .redeemed:
            "gift.fill"
        case .adjusted:
            "slider.horizontal.3"
        }
    }

    private var pointsTint: Color {
        entry.points >= 0 ? DS.ColorToken.success : DS.ColorToken.danger
    }

    private var pointsText: String {
        entry.points > 0 ? "+\(entry.points)" : "\(entry.points)"
    }
}

@MainActor
private struct LoyaltyAdjustmentSheet: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case add
        case deduct

        var id: String { rawValue }
        var title: String {
            switch self {
            case .add:
                AppLocalization.localized("loyalty.adjust.add", value: "Add")
            case .deduct:
                AppLocalization.localized("loyalty.adjust.deduct", value: "Deduct")
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable var client: Client
    @State private var mode: Mode = .add
    @State private var amountText = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(AppLocalization.localized("loyalty.adjust.section", value: "Adjustment")) {
                    Picker(AppLocalization.localized("loyalty.adjust.mode", value: "Mode"), selection: $mode) {
                        ForEach(Mode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    TextField(AppLocalization.localized("loyalty.adjust.points_field", value: "Points"), text: $amountText)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .accessibilityIdentifier("loyaltyAdjustment.pointsField")
                }

                Section {
                    HStack {
                        Text(AppLocalization.localized("loyalty.adjust.current_balance", value: "Current Balance"))
                        Spacer()
                        Text(LoyaltyCopy.points(client.loyaltyPoints))
                            .foregroundStyle(.secondary)
                    }
                    if let previewDelta {
                        HStack {
                            Text(AppLocalization.localized("loyalty.adjust.new_balance", value: "New Balance"))
                            Spacer()
                            Text(LoyaltyCopy.points(client.loyaltyPoints + previewDelta))
                                .foregroundStyle(previewDelta < 0 && abs(previewDelta) > client.loyaltyPoints ? DS.ColorToken.danger : .secondary)
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(DS.ColorToken.danger)
                    }
                }
            }
            .navigationTitle(AppLocalization.localized("loyalty.adjust.title", value: "Adjust Points"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.localized("common.cancel", value: "Cancel")) { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? AppLocalization.localized("loyalty.adjust.saving", value: "Saving") : AppLocalization.localized("loyalty.adjust.apply", value: "Apply")) {
                        applyAdjustment()
                    }
                    .disabled(!canApply || isSaving)
                    .accessibilityIdentifier("loyaltyAdjustment.apply")
                }
            }
        }
    }

    private var parsedAmount: Int? {
        Int(amountText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var previewDelta: Int? {
        guard let parsedAmount, parsedAmount > 0 else { return nil }
        return mode == .add ? parsedAmount : -parsedAmount
    }

    private var canApply: Bool {
        guard let previewDelta else { return false }
        return client.loyaltyPoints + previewDelta >= 0
    }

    private func applyAdjustment() {
        guard let previewDelta, canApply else { return }
        isSaving = true
        errorMessage = nil

        Task {
            do {
                let service = LoyaltyService(modelContainer: modelContext.container)
                try await service.adjustPoints(clientUUID: client.uuid, delta: previewDelta)
                HapticManager.notify(.success)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                HapticManager.notify(.error)
            }
            isSaving = false
        }
    }
}
