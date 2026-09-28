import SwiftData
import SwiftUI

@MainActor
struct ClientLoyaltyView: View {
    private enum SheetDestination: Identifiable {
        case adjustment
        case catalog

        var id: String {
            switch self {
            case .adjustment:
                "adjustment"
            case .catalog:
                "catalog"
            }
        }
    }

    @Bindable var client: Client
    @Query private var ledgerEntries: [LoyaltyLedgerEntry]
    @Query(
        filter: #Predicate<LoyaltyRewardTemplate> { $0.isEnabled == true },
        sort: \LoyaltyRewardTemplate.sortOrder,
        order: .forward
    ) private var rewardTemplates: [LoyaltyRewardTemplate]
    @Query(sort: \LoyaltyRewardTemplate.sortOrder, order: .forward) private var allRewardTemplates: [LoyaltyRewardTemplate]
    @Query(sort: \LoyaltyConfig.createdAt, order: .forward) private var configs: [LoyaltyConfig]
    @State private var sheetDestination: SheetDestination?
    @State private var animatedTierProgress: Double = 0

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
            VStack(alignment: .leading, spacing: 16) {
                balanceCard
                rewardProgressCard
                quickActions
                smartStatsGrid
                tierCard
                ledgerSection
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
        .sheet(item: $sheetDestination) { destination in
            switch destination {
            case .adjustment:
                LoyaltyAdjustmentSheet(client: client)
            case .catalog:
                RewardsCatalogView(client: client)
            }
        }
    }

    private var balanceCard: some View {
        Card(
            cornerRadius: 18,
            padding: EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18),
            accent: .top(.gradient(LinearGradient(
                colors: [DS.ColorToken.warning, DS.ColorToken.info],
                startPoint: .leading,
                endPoint: .trailing
            )))
        ) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Image(systemName: tier.systemImage)
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 42, height: 42)
                                .background(tier.tint.gradient, in: RoundedRectangle(cornerRadius: 13, style: .continuous))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(client.fullName)
                                    .font(.headline)
                                Text(String(format: AppLocalization.localized("loyalty.client.member_fmt", value: "%1$@ member • %2$@ earn rate"), tier.displayName, tier.earnRateText))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        loyaltyCoachMessage
                    }

                    Spacer(minLength: 12)

                    LoyaltyPointsBadge(client: client, scale: .prominent)
                }
            }
        }
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(format: AppLocalization.localized("loyalty.client.balance_accessibility_fmt", value: "%1$@, %2$d loyalty points, %3$@ tier"), client.fullName, client.loyaltyPoints, tier.displayName))
    }

    private var loyaltyCoachMessage: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: loyaltyCoachSymbol)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(loyaltyCoachTint)
                .frame(width: 26, height: 26)
                .background(loyaltyCoachTint.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(loyaltyCoachTitle)
                    .font(.subheadline.weight(.bold))
                Text(loyaltyCoachBody)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 2)
    }

    private var smartStatsGrid: some View {
        LazyVGrid(columns: smartStatColumns, spacing: 10) {
            LoyaltySmartStatCard(
                title: AppLocalization.localized("loyalty.client.stat.ready", value: "Ready Rewards"),
                value: "\(redeemableRewards.count)",
                detail: rewardCatalog.isEmpty
                    ? AppLocalization.localized("loyalty.client.stat.catalog_paused", value: "Catalog paused")
                    : AppLocalization.localized("loyalty.client.stat.can_redeem", value: "Can redeem now"),
                systemImage: "gift.fill",
                tint: bestRedeemableReward?.style.tint ?? DS.ColorToken.info
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
                tint: tier.tint
            )
        }
        .padding(.horizontal)
    }

    private var smartStatColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 160), spacing: 10)]
    }

    private var rewardProgressCard: some View {
        Card(
            cornerRadius: 18,
            padding: EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18),
            accent: .leading(.color(rewardProgressTint), thickness: 4)
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: rewardProgressSymbol)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(rewardProgressTint.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(rewardProgressTitle)
                            .font(.headline)
                        Text(rewardProgressDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    if let nextReward {
                        Text(String(format: AppLocalization.localized("loyalty.client.points_short_fmt", value: "%d pts"), max(0, nextReward.pointCost - client.loyaltyPoints)))
                            .font(.caption.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(rewardProgressTint)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(rewardProgressTint.opacity(0.12), in: Capsule())
                    }
                }

                if !rewardCatalog.isEmpty {
                    ProgressView(value: nextRewardProgress)
                        .tint(rewardProgressTint)
                    Text(nextRewardText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("clientLoyalty.rewardProgress")
    }

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

                    if let next = tier.next {
                        Text(next.displayName)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(next.tint)
                            .padding(.vertical, 3)
                            .padding(.horizontal, 8)
                            .background(Capsule().fill(next.tint.opacity(0.14)))
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: animatedTierProgress)
                        .tint(tier.next?.tint ?? tier.tint)
                    Text(tierProgressText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                tierLadder
            }
        }
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tierAccessibilityLabel)
        .accessibilityIdentifier("clientLoyalty.tierCard")
        .task {
            withAnimation(MotionSystem.fluid.delay(0.15)) {
                animatedTierProgress = LoyaltyEngine.tierProgress(lifetimeEarned: lifetimeEarned)
            }
        }
        .onChange(of: lifetimeEarned) { _, newValue in
            withAnimation(MotionSystem.fluid) {
                animatedTierProgress = LoyaltyEngine.tierProgress(lifetimeEarned: newValue)
            }
        }
    }

    private var tierLadder: some View {
        HStack(spacing: 8) {
            ForEach(LoyaltyTier.allCases, id: \.self) { ladderTier in
                let isCurrentOrUnlocked = lifetimeEarned >= ladderTier.threshold
                let accessibilityDetail = isCurrentOrUnlocked
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
                .foregroundStyle(isCurrentOrUnlocked ? .white : ladderTier.tint)
                .padding(.vertical, 5)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity)
                .background(
                    isCurrentOrUnlocked ? ladderTier.tint : ladderTier.tint.opacity(0.12),
                    in: Capsule()
                )
                .accessibilityLabel(String(format: AppLocalization.localized("loyalty.client.ladder_accessibility_fmt", value: "%1$@ tier, %2$@"), ladderTier.displayName, accessibilityDetail))
            }
        }
    }

    private var quickActions: some View {
        HStack(spacing: 12) {
            Button {
                sheetDestination = .catalog
            } label: {
                Label(
                    bestRedeemableReward == nil
                        ? AppLocalization.localized("loyalty.client.view_rewards", value: "View Rewards")
                        : AppLocalization.localized("loyalty.client.redeem_best", value: "Redeem Best Reward"),
                    systemImage: "gift.fill"
                )
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background((bestRedeemableReward?.style.tint ?? DS.ColorToken.info), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .pressScaleStyle(hapticsEnabled: true)
            .accessibilityLabel(AppLocalization.localized("loyalty.client.redeem_rewards_accessibility", value: "Redeem rewards"))
            .accessibilityIdentifier("clientLoyalty.redeemRewards")

            Button {
                sheetDestination = .adjustment
            } label: {
                Label(AppLocalization.localized("loyalty.client.adjust_balance", value: "Adjust Balance"), systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))
                    .frame(minWidth: 104)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 14)
                    .background(DS.ColorToken.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .pressScaleStyle(hapticsEnabled: true)
            .accessibilityLabel(AppLocalization.localized("loyalty.client.adjust_accessibility", value: "Adjust loyalty points"))
            .accessibilityIdentifier("clientLoyalty.adjustPoints")
        }
        .padding(.horizontal)
    }

    private var ledgerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(AppLocalization.localized("loyalty.client.ledger_title", value: "Points Ledger"))
                    .font(.headline)
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
                    ForEach(ledgerEntries) { entry in
                        LoyaltyLedgerEntryRow(entry: entry)
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.bottom, 24)
    }

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
        guard configs.first?.isRewardsCatalogEnabled ?? true else { return [] }
        let persistentRewards = rewardTemplates.map(\.displayReward)
        return persistentRewards.isEmpty && allRewardTemplates.isEmpty ? LoyaltyReward.builtInCatalog : persistentRewards
    }

    private var rewardsByCost: [LoyaltyReward] {
        rewardCatalog.sorted { first, second in
            if first.pointCost == second.pointCost {
                return first.title.localizedStandardCompare(second.title) == .orderedAscending
            }
            return first.pointCost < second.pointCost
        }
    }

    private var redeemableRewards: [LoyaltyReward] {
        rewardsByCost.filter { $0.isRedeemable(with: client.loyaltyPoints) }
    }

    private var bestRedeemableReward: LoyaltyReward? {
        redeemableRewards.last
    }

    private var nextReward: LoyaltyReward? {
        rewardsByCost.first { $0.pointCost > client.loyaltyPoints }
    }

    private var previousRewardCost: Int {
        rewardsByCost.last { $0.pointCost <= client.loyaltyPoints }?.pointCost ?? 0
    }

    private var nextRewardProgress: Double {
        guard !rewardCatalog.isEmpty else { return 0 }
        guard let nextReward else { return 1 }
        let span = max(1, nextReward.pointCost - previousRewardCost)
        return min(1, max(0, Double(client.loyaltyPoints - previousRewardCost) / Double(span)))
    }

    private var nextRewardText: String {
        if rewardCatalog.isEmpty {
            return AppLocalization.localized("loyalty.client.rewards_paused_settings", value: "Rewards are paused in Loyalty settings")
        }
        if let nextReward {
            let remaining = max(0, nextReward.pointCost - client.loyaltyPoints)
            return String(format: AppLocalization.localized("loyalty.client.points_until_fmt", value: "%1$d points until %2$@"), remaining, nextReward.title)
        }
        return AppLocalization.localized("loyalty.client.all_unlocked", value: "Every active reward is unlocked")
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

    private var projectedVisitsToNextReward: Int? {
        guard let nextReward else { return nil }
        let remaining = max(0, nextReward.pointCost - client.loyaltyPoints)
        guard remaining > 0, averageEarnedPerVisit > 0 else { return nil }
        return max(1, Int(ceil(Double(remaining) / Double(averageEarnedPerVisit))))
    }

    private func signedPointsText(_ value: Int) -> String {
        value > 0 ? "+\(value)" : "\(value)"
    }

    private var loyaltyCoachSymbol: String {
        if rewardCatalog.isEmpty { return "pause.circle.fill" }
        if bestRedeemableReward != nil { return "sparkles" }
        if nextReward != nil { return "target" }
        return "crown.fill"
    }

    private var loyaltyCoachTint: Color {
        if rewardCatalog.isEmpty { return DS.ColorToken.warning }
        if let bestRedeemableReward { return bestRedeemableReward.style.tint }
        if let nextReward { return nextReward.style.tint }
        return tier.tint
    }

    private var loyaltyCoachTitle: String {
        if rewardCatalog.isEmpty { return AppLocalization.localized("loyalty.client.coach.paused_title", value: "Rewards paused") }
        if bestRedeemableReward != nil { return AppLocalization.localized("loyalty.client.coach.ready_title", value: "Ready to reward") }
        if let nextReward { return String(format: AppLocalization.localized("loyalty.client.coach.next_title_fmt", value: "Next up: %@"), nextReward.title) }
        return AppLocalization.localized("loyalty.client.coach.vip_title", value: "VIP-ready balance")
    }

    private var loyaltyCoachBody: String {
        if rewardCatalog.isEmpty {
            return AppLocalization.localized("loyalty.client.coach.paused_body", value: "Turn the catalog back on in Loyalty settings when the shop is ready.")
        }
        if let bestRedeemableReward {
            let remainingAfterRedeem = max(0, client.loyaltyPoints - bestRedeemableReward.pointCost)
            return String(format: AppLocalization.localized("loyalty.client.coach.ready_body_fmt", value: "%1$@ can redeem %2$@ now and keep %3$d points."), client.firstName, bestRedeemableReward.title, remainingAfterRedeem)
        }
        guard let nextReward else {
            return String(format: AppLocalization.localized("loyalty.client.coach.all_body_fmt", value: "%@ has enough points for every active reward."), client.firstName)
        }

        let remaining = max(0, nextReward.pointCost - client.loyaltyPoints)
        if let projectedVisitsToNextReward {
            if projectedVisitsToNextReward == 1 {
                return String(format: AppLocalization.localized("loyalty.client.coach.pace_one_fmt", value: "%d more points, roughly 1 visit at the current pace."), remaining)
            }
            return String(format: AppLocalization.localized("loyalty.client.coach.pace_fmt", value: "%1$d more points, roughly %2$d visits at the current pace."), remaining, projectedVisitsToNextReward)
        }
        return String(format: AppLocalization.localized("loyalty.client.coach.no_pace_fmt", value: "%d more points needed. Complete a checkout to start projecting visit pace."), remaining)
    }

    private var rewardProgressTint: Color {
        if rewardCatalog.isEmpty { return DS.ColorToken.warning }
        return bestRedeemableReward?.style.tint ?? nextReward?.style.tint ?? tier.tint
    }

    private var rewardProgressSymbol: String {
        if rewardCatalog.isEmpty { return "gift" }
        return bestRedeemableReward?.systemImage ?? nextReward?.systemImage ?? "crown.fill"
    }

    private var rewardProgressTitle: String {
        if rewardCatalog.isEmpty { return AppLocalization.localized("loyalty.client.progress.paused_title", value: "Rewards catalog is paused") }
        if let bestRedeemableReward { return String(format: AppLocalization.localized("loyalty.client.progress.ready_title_fmt", value: "%@ is ready"), bestRedeemableReward.title) }
        if let nextReward { return String(format: AppLocalization.localized("loyalty.client.progress.next_title_fmt", value: "Progress to %@"), nextReward.title) }
        return AppLocalization.localized("loyalty.client.progress.all_title", value: "All active rewards unlocked")
    }

    private var rewardProgressDetail: String {
        if rewardCatalog.isEmpty {
            return AppLocalization.localized("loyalty.client.progress.paused_detail", value: "Clients can still earn points, but reward redemption is hidden until the catalog is enabled.")
        }
        if let bestRedeemableReward {
            let otherReadyCount = max(0, redeemableRewards.count - 1)
            if otherReadyCount > 0 {
                return String(format: AppLocalization.localized("loyalty.client.progress.several_ready_fmt", value: "%1$@ has %2$d rewards available. The highest-value option costs %3$d points."), client.firstName, otherReadyCount + 1, bestRedeemableReward.pointCost)
            }
            return String(format: AppLocalization.localized("loyalty.client.progress.one_ready_fmt", value: "%@ can redeem this reward from the catalog now."), client.firstName)
        }
        if let projectedVisitsToNextReward {
            if projectedVisitsToNextReward == 1 {
                return String(format: AppLocalization.localized("loyalty.client.progress.pace_one_fmt", value: "At about %d points per earning visit, this is around 1 visit away."), averageEarnedPerVisit)
            }
            return String(format: AppLocalization.localized("loyalty.client.progress.pace_fmt", value: "At about %1$d points per earning visit, this is around %2$d visits away."), averageEarnedPerVisit, projectedVisitsToNextReward)
        }
        return AppLocalization.localized("loyalty.client.progress.no_history", value: "No earning history yet, so the next reward projection will appear after a checkout.")
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
                try await service.adjustPoints(client: client, delta: previewDelta)
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
