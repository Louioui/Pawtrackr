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
        .navigationTitle("Loyalty & Rewards")
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
                                Text("\(tier.displayName) member • \(tier.earnRateText) earn rate")
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
        .accessibilityLabel("\(client.fullName), \(client.loyaltyPoints) loyalty points, \(tier.displayName) tier")
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
                title: "Ready Rewards",
                value: "\(redeemableRewards.count)",
                detail: rewardCatalog.isEmpty ? "Catalog paused" : "Can redeem now",
                systemImage: "gift.fill",
                tint: bestRedeemableReward?.style.tint ?? DS.ColorToken.info
            )

            LoyaltySmartStatCard(
                title: "30-Day Change",
                value: signedPointsText(pointsDelta30Days),
                detail: pointsDelta30Days >= 0 ? "Net points gained" : "Net points spent",
                systemImage: pointsDelta30Days >= 0 ? "chart.line.uptrend.xyaxis" : "arrow.down.circle.fill",
                tint: pointsDelta30Days >= 0 ? DS.ColorToken.success : DS.ColorToken.danger
            )

            LoyaltySmartStatCard(
                title: "Avg Earn",
                value: averageEarnedPerVisit > 0 ? "\(averageEarnedPerVisit)" : "—",
                detail: averageEarnedPerVisit > 0 ? "Points per visit" : "No visits yet",
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
                        Text("\(max(0, nextReward.pointCost - client.loyaltyPoints)) pts")
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
                        Text("\(tier.displayName) Tier")
                            .font(.subheadline.weight(.bold))
                        Text("Every visit earns \(tier.earnRateText) points")
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
                    ? "unlocked"
                    : "\(max(0, ladderTier.threshold - lifetimeEarned)) points away"
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
                .accessibilityLabel("\(ladderTier.displayName) tier, \(accessibilityDetail)")
            }
        }
    }

    private var quickActions: some View {
        HStack(spacing: 12) {
            Button {
                sheetDestination = .catalog
            } label: {
                Label(bestRedeemableReward == nil ? "View Rewards" : "Redeem Best Reward", systemImage: "gift.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background((bestRedeemableReward?.style.tint ?? DS.ColorToken.info), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .pressScaleStyle(hapticsEnabled: true)
            .accessibilityLabel("Redeem rewards")
            .accessibilityIdentifier("clientLoyalty.redeemRewards")

            Button {
                sheetDestination = .adjustment
            } label: {
                Label("Adjust Balance", systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))
                    .frame(minWidth: 104)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 14)
                    .background(DS.ColorToken.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .pressScaleStyle(hapticsEnabled: true)
            .accessibilityLabel("Adjust loyalty points")
            .accessibilityIdentifier("clientLoyalty.adjustPoints")
        }
        .padding(.horizontal)
    }

    private var ledgerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Points Ledger")
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
                    "No Loyalty History",
                    systemImage: "clock.arrow.2.circlepath",
                    description: Text("Earned points, redemptions, and adjustments will appear here.")
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
            return "\(remaining) earned points until \(next.displayName) (\(next.earnRateText) earn rate)"
        }
        return "Top tier reached — every visit earns \(tier.earnRateText) points"
    }

    private var tierAccessibilityLabel: String {
        if let next = tier.next, let remaining = LoyaltyEngine.pointsUntilNextTier(lifetimeEarned: lifetimeEarned) {
            return "\(tier.displayName) tier, \(remaining) points until \(next.displayName)"
        }
        return "\(tier.displayName) tier, top tier"
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
            return "Rewards are paused in Loyalty settings"
        }
        if let nextReward {
            let remaining = max(0, nextReward.pointCost - client.loyaltyPoints)
            return "\(remaining) points until \(nextReward.title)"
        }
        return "Every active reward is unlocked"
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
        if rewardCatalog.isEmpty { return "Rewards paused" }
        if bestRedeemableReward != nil { return "Ready to reward" }
        if let nextReward { return "Next up: \(nextReward.title)" }
        return "VIP-ready balance"
    }

    private var loyaltyCoachBody: String {
        if rewardCatalog.isEmpty {
            return "Turn the catalog back on in Loyalty settings when the shop is ready."
        }
        if let bestRedeemableReward {
            let remainingAfterRedeem = max(0, client.loyaltyPoints - bestRedeemableReward.pointCost)
            return "\(client.firstName) can redeem \(bestRedeemableReward.title) now and keep \(remainingAfterRedeem) points."
        }
        guard let nextReward else {
            return "\(client.firstName) has enough points for every active reward."
        }

        let remaining = max(0, nextReward.pointCost - client.loyaltyPoints)
        if let projectedVisitsToNextReward {
            return "\(remaining) more points, roughly \(projectedVisitsToNextReward) visit\(projectedVisitsToNextReward == 1 ? "" : "s") at the current pace."
        }
        return "\(remaining) more points needed. Complete a checkout to start projecting visit pace."
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
        if rewardCatalog.isEmpty { return "Rewards catalog is paused" }
        if let bestRedeemableReward { return "\(bestRedeemableReward.title) is ready" }
        if let nextReward { return "Progress to \(nextReward.title)" }
        return "All active rewards unlocked"
    }

    private var rewardProgressDetail: String {
        if rewardCatalog.isEmpty {
            return "Clients can still earn points, but reward redemption is hidden until the catalog is enabled."
        }
        if let bestRedeemableReward {
            let otherReadyCount = max(0, redeemableRewards.count - 1)
            if otherReadyCount > 0 {
                return "\(client.firstName) has \(otherReadyCount + 1) rewards available. The highest-value option costs \(bestRedeemableReward.pointCost) points."
            }
            return "\(client.firstName) can redeem this reward from the catalog now."
        }
        if let projectedVisitsToNextReward {
            return "At about \(averageEarnedPerVisit) points per earning visit, this is around \(projectedVisitsToNextReward) visit\(projectedVisitsToNextReward == 1 ? "" : "s") away."
        }
        return "No earning history yet, so the next reward projection will appear after a checkout."
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
                            Text("Balance \(balance)")
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
            entry.reason.map { "Visit — \($0)" } ?? "Visit checkout"
        case .redeemed:
            entry.reason ?? "Reward redeemed"
        case .adjusted:
            entry.reason ?? "Manual adjustment"
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
                "Add"
            case .deduct:
                "Deduct"
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
                Section("Adjustment") {
                    Picker("Mode", selection: $mode) {
                        ForEach(Mode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    TextField("Points", text: $amountText)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .accessibilityIdentifier("loyaltyAdjustment.pointsField")
                }

                Section {
                    HStack {
                        Text("Current Balance")
                        Spacer()
                        Text("\(client.loyaltyPoints) points")
                            .foregroundStyle(.secondary)
                    }
                    if let previewDelta {
                        HStack {
                            Text("New Balance")
                            Spacer()
                            Text("\(client.loyaltyPoints + previewDelta) points")
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
            .navigationTitle("Adjust Points")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving" : "Apply") {
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
