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
                tierCard
                quickActions
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
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: tier.systemImage)
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(tier.tint.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(client.fullName)
                            .font(.headline)
                        Text("\(tier.displayName) member • Earning \(tier.earnRateText) points")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 12)

                    LoyaltyPointsBadge(client: client, scale: .prominent)
                }

                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: nextRewardProgress)
                        .tint(DS.ColorToken.warning)
                    Text(nextRewardText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(client.fullName), \(client.loyaltyPoints) loyalty points, \(tier.displayName) tier")
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

    private var quickActions: some View {
        HStack(spacing: 12) {
            Button {
                sheetDestination = .catalog
            } label: {
                Label("Redeem Rewards", systemImage: "gift.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(DS.ColorToken.info, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .pressScaleStyle(hapticsEnabled: true)
            .accessibilityLabel("Redeem rewards")
            .accessibilityIdentifier("clientLoyalty.redeemRewards")

            Button {
                sheetDestination = .adjustment
            } label: {
                Label("Adjust", systemImage: "slider.horizontal.3")
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

    private var nextReward: LoyaltyReward? {
        LoyaltyReward.builtInCatalog.first { $0.pointCost > client.loyaltyPoints }
    }

    private var nextRewardProgress: Double {
        guard let nextReward else { return 1 }
        let previousCost = LoyaltyReward.builtInCatalog
            .last { $0.pointCost <= client.loyaltyPoints }?
            .pointCost ?? 0
        let span = max(1, nextReward.pointCost - previousCost)
        return min(1, max(0, Double(client.loyaltyPoints - previousCost) / Double(span)))
    }

    private var nextRewardText: String {
        if let nextReward {
            let remaining = max(0, nextReward.pointCost - client.loyaltyPoints)
            return "\(remaining) points until \(nextReward.title)"
        }
        return "All built-in rewards are unlocked"
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
