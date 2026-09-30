import SwiftData
import SwiftUI

@MainActor
struct LoyaltyManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(EntitlementStore.self) private var entitlements

    @Query(sort: \LoyaltyConfig.createdAt, order: .forward) private var configs: [LoyaltyConfig]
    @Query(sort: \LoyaltyRewardTemplate.sortOrder, order: .forward) private var rewards: [LoyaltyRewardTemplate]

    @State private var errorMessage: String?
    @State private var newRewardTitle = ""
    @State private var newRewardDetail = ""
    @State private var newRewardCost = 100
    @State private var newRewardStyle: LoyaltyReward.Style = .credit
    @State private var newRewardBenefitKind: NewRewardBenefitKind = .amountOff
    @State private var newRewardBenefitValue = 10
    @State private var showResetCatalogConfirmation = false

    private var config: LoyaltyConfig? {
        configs.first
    }

    private var canEdit: Bool {
        entitlements.isPremium
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !canEdit {
                lockedCard
            }

            earningRulesCard
                .disabled(!canEdit)

            // Read-only preview of the rules above, with the same math
            // checkout uses. It stays usable without Pro: it changes nothing.
            LoyaltySimulatorCard()
                .walkthroughTarget(.loyaltySimulator)

            rewardsCatalogCard
                .disabled(!canEdit || !(config?.isRewardsCatalogEnabled ?? true))

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(DS.ColorToken.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task {
            // Seed only after this device's first iCloud import has settled,
            // like startup maintenance: on a device that just joined, the
            // owner's reward catalog may still be downloading, and seeding
            // "because it's empty" would upload a second catalog beside it.
            // Local-only / signed-out devices don't wait.
            let monitor = CloudKitMonitor.shared
            if monitor.accountState.isAvailable, !monitor.firstSyncCompleted {
                await monitor.awaitFirstSyncSettled(timeout: .seconds(30))
            }
            guard !Task.isCancelled else { return }
            DataMigrations.ensureLoyaltyDefaults(in: modelContext)
        }
        .confirmationDialog(
            AppLocalization.localized("loyalty2.reset.title", value: "Switch to the Rewards 2.0 catalog?"),
            isPresented: $showResetCatalogConfirmation,
            titleVisibility: .visible
        ) {
            Button(AppLocalization.localized("loyalty2.reset.action", value: "Use Rewards 2.0"), role: .destructive) {
                resetToDiscountLadder()
            }
            Button(AppLocalization.localized("common.cancel", value: "Cancel"), role: .cancel) {}
        } message: {
            Text(AppLocalization.localized(
                "loyalty2.reset.message",
                value: "This replaces the current rewards with $5 Off, $20 Off, 25% Off and Free Bath, which checkout takes off the bill by itself. Client point balances stay unchanged."
            ))
        }
    }

    private var lockedCard: some View {
        Card(cornerRadius: 12, accent: .leading(.color(DS.ColorToken.warning))) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(DS.ColorToken.warning, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(AppLocalization.localized("loyalty.settings.pro_title", value: "Pawtrackr Pro"))
                        .font(.headline)
                    Text(AppLocalization.localized("loyalty.settings.pro_detail", value: "Loyalty configuration is available with active Pro access."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var earningRulesCard: some View {
        Card(cornerRadius: 12, accent: .leading(.color(DS.ColorToken.warning))) {
            VStack(alignment: .leading, spacing: 14) {
                Label(AppLocalization.localized("loyalty.settings.earning_rules", value: "Loyalty Earning Rules"), systemImage: "star.circle.fill")
                    .font(.headline)

                Picker(AppLocalization.localized("loyalty.settings.earning_mode", value: "Earning Mode"), selection: earnModeBinding) {
                    ForEach(LoyaltyEarnMode.allCases, id: \.self) { mode in
                        Text(mode.displayTitle).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("loyaltySettings.earnMode")

                switch earnModeBinding.wrappedValue {
                case .pointsPerDollar:
                    Stepper(value: pointsPerDollarBinding, in: 0...50, step: 1) {
                        settingsValueRow(
                            title: AppLocalization.localized("loyalty.settings.points_per_dollar", value: "Points per dollar"),
                            value: "\(pointsPerDollarBinding.wrappedValue)"
                        )
                    }
                    .accessibilityIdentifier("loyaltySettings.pointsPerDollar")
                case .flatPerVisit:
                    Stepper(value: pointsPerVisitBinding, in: 0...500, step: 5) {
                        settingsValueRow(
                            title: AppLocalization.localized("loyalty.settings.flat_visit_points", value: "Flat visit points"),
                            value: "\(pointsPerVisitBinding.wrappedValue)"
                        )
                    }
                    .accessibilityIdentifier("loyaltySettings.pointsPerVisit")
                }

                Stepper(value: thresholdBinding, in: 1...10_000, step: 25) {
                    settingsValueRow(
                        title: AppLocalization.localized("loyalty.settings.reward_threshold", value: "Reward threshold"),
                        value: "\(thresholdBinding.wrappedValue)"
                    )
                }
                .accessibilityIdentifier("loyaltySettings.redemptionThreshold")

                Toggle(isOn: catalogEnabledBinding) {
                    Label(AppLocalization.localized("loyalty.catalog.title", value: "Rewards Catalog"), systemImage: "gift.fill")
                }
                .accessibilityIdentifier("loyaltySettings.catalogEnabled")
            }
        }
    }

    private var rewardsCatalogCard: some View {
        Card(cornerRadius: 12, accent: .leading(.color(DS.ColorToken.info))) {
            VStack(alignment: .leading, spacing: 14) {
                Label(AppLocalization.localized("loyalty.settings.templates", value: "Reward Templates"), systemImage: "giftcard.fill")
                    .font(.headline)

                Button {
                    showResetCatalogConfirmation = true
                } label: {
                    Label(
                        AppLocalization.localized("loyalty2.reset.action", value: "Use Rewards 2.0"),
                        systemImage: "arrow.counterclockwise.circle.fill"
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(rewards.isEmpty)
                .accessibilityIdentifier("loyaltySettings.useRewards2")

                if rewards.isEmpty {
                    ContentUnavailableView(
                        AppLocalization.localized("loyalty.settings.no_rewards_title", value: "No Rewards"),
                        systemImage: "gift",
                        description: Text(AppLocalization.localized("loyalty.settings.no_rewards_detail", value: "Default rewards are added on launch."))
                    )
                    .frame(maxWidth: .infinity)
                } else {
                    VStack(spacing: 10) {
                        ForEach(rewards) { reward in
                            rewardTemplateRow(reward)
                        }
                    }
                }

                Divider()

                addRewardForm
            }
        }
    }

    private var addRewardForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(AppLocalization.localized("loyalty.settings.reward_title_field", value: "Reward title"), text: $newRewardTitle)
                .textFieldStyle(.roundedBorder)
                .textLengthLimit($newRewardTitle, to: TextInputLimits.name)
                .accessibilityIdentifier("loyaltySettings.newRewardTitle")

            TextField(AppLocalization.localized("loyalty.settings.reward_detail_field", value: "Reward detail"), text: $newRewardDetail)
                .textFieldStyle(.roundedBorder)
                .textLengthLimit($newRewardDetail, to: TextInputLimits.notes)
                .accessibilityIdentifier("loyaltySettings.newRewardDetail")

            Stepper(value: $newRewardCost, in: 1...10_000, step: 25) {
                settingsValueRow(title: AppLocalization.localized("loyalty.settings.cost", value: "Cost"), value: LoyaltyCopy.points(newRewardCost))
            }
            .accessibilityIdentifier("loyaltySettings.newRewardCost")

            Picker(AppLocalization.localized("loyalty.settings.style", value: "Style"), selection: $newRewardStyle) {
                ForEach(LoyaltyReward.Style.allCases, id: \.self) { style in
                    Label(style.displayTitle, systemImage: style.systemImage)
                        .tag(style)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("loyaltySettings.newRewardStyle")

            Picker(AppLocalization.localized("loyalty2.settings.benefit", value: "At checkout"), selection: $newRewardBenefitKind) {
                ForEach(NewRewardBenefitKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("loyaltySettings.newRewardBenefit")
            .onChange(of: newRewardBenefitKind) { _, kind in
                newRewardBenefitValue = kind == .percentOff ? 25 : 10
            }

            switch newRewardBenefitKind {
            case .amountOff:
                Stepper(value: $newRewardBenefitValue, in: 1...500) {
                    settingsValueRow(
                        title: AppLocalization.localized("loyalty2.settings.amount_off", value: "Amount off"),
                        value: LoyaltyMoney.compact(Decimal(newRewardBenefitValue))
                    )
                }
                .accessibilityIdentifier("loyaltySettings.newRewardAmount")
            case .percentOff:
                Stepper(value: $newRewardBenefitValue, in: 1...100, step: 5) {
                    settingsValueRow(
                        title: AppLocalization.localized("loyalty2.settings.percent_off", value: "Percent off"),
                        value: "\(newRewardBenefitValue)%"
                    )
                }
                .accessibilityIdentifier("loyaltySettings.newRewardPercent")
            case .freeBath, .manual:
                EmptyView()
            }

            Button {
                createReward()
            } label: {
                Label(AppLocalization.localized("loyalty.settings.add_reward", value: "Add Reward"), systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .pressScaleStyle(hapticsEnabled: true)
            .disabled(newRewardTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("loyaltySettings.addReward")
        }
    }

    private func settingsValueRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func rewardTemplateRow(_ reward: LoyaltyRewardTemplate) -> some View {
        Toggle(isOn: enabledBinding(for: reward)) {
            HStack(spacing: 12) {
                Image(systemName: reward.style.systemImage)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(reward.style.tint, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(LoyaltyCopy.title(for: reward.displayReward))
                        .font(.subheadline.weight(.semibold))
                    Text(String(
                        format: AppLocalization.localized("loyalty2.settings.reward_row_fmt", value: "%1$@ · %2$@"),
                        LoyaltyCopy.points(reward.pointCost),
                        reward.displayReward.benefitSummary
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityIdentifier("loyaltySettings.reward.\(reward.uuid.uuidString).enabled")
    }

    private var earnModeBinding: Binding<LoyaltyEarnMode> {
        Binding {
            config?.earnMode ?? .pointsPerDollar
        } set: { mode in
            updateConfig(earnMode: mode)
        }
    }

    private var pointsPerDollarBinding: Binding<Int> {
        Binding {
            NSDecimalNumber(decimal: config?.pointsPerDollar ?? Decimal(1)).intValue
        } set: { value in
            updateConfig(pointsPerDollar: Decimal(value))
        }
    }

    private var pointsPerVisitBinding: Binding<Int> {
        Binding {
            config?.pointsPerVisit ?? 20
        } set: { value in
            updateConfig(pointsPerVisit: value)
        }
    }

    private var thresholdBinding: Binding<Int> {
        Binding {
            config?.redemptionThreshold ?? 100
        } set: { value in
            updateConfig(redemptionThreshold: value)
        }
    }

    private var catalogEnabledBinding: Binding<Bool> {
        Binding {
            config?.isRewardsCatalogEnabled ?? true
        } set: { enabled in
            updateConfig(isRewardsCatalogEnabled: enabled)
        }
    }

    private func enabledBinding(for reward: LoyaltyRewardTemplate) -> Binding<Bool> {
        Binding {
            reward.isEnabled
        } set: { enabled in
            mutate { service in
                try await service.setRewardTemplate(reward, isEnabled: enabled)
            }
        }
    }

    private func updateConfig(
        earnMode: LoyaltyEarnMode? = nil,
        pointsPerDollar: Decimal? = nil,
        pointsPerVisit: Int? = nil,
        redemptionThreshold: Int? = nil,
        isRewardsCatalogEnabled: Bool? = nil
    ) {
        mutate { service in
            try await service.updateConfig(
                earnMode: earnMode,
                pointsPerDollar: pointsPerDollar,
                pointsPerVisit: pointsPerVisit,
                redemptionThreshold: redemptionThreshold,
                isRewardsCatalogEnabled: isRewardsCatalogEnabled
            )
        }
    }

    private func createReward() {
        let title = newRewardTitle
        let detail = newRewardDetail.isEmpty
            ? AppLocalization.localized("loyalty.settings.custom_reward_detail", value: "Custom loyalty reward.")
            : newRewardDetail
        let cost = newRewardCost
        let style = newRewardStyle
        let benefit = newRewardBenefitKind.benefit(value: newRewardBenefitValue)

        mutate { service in
            try await service.createRewardTemplate(
                title: title,
                detail: detail,
                pointCost: cost,
                systemImage: style.systemImage,
                style: style,
                benefit: benefit
            )
            newRewardTitle = ""
            newRewardDetail = ""
            newRewardCost = 100
            newRewardStyle = .credit
            newRewardBenefitKind = .amountOff
            newRewardBenefitValue = 10
        }
    }

    private func resetToDiscountLadder() {
        mutate { service in
            try await service.resetRewardTemplatesToDiscountLadder()
        }
    }

    private func mutate(_ operation: @escaping (LoyaltyService) async throws -> Void) {
        Task {
            do {
                let service = LoyaltyService(modelContainer: modelContext.container)
                try await operation(service)
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// What a new reward takes off at checkout, as the add-reward form offers it.
private enum NewRewardBenefitKind: String, CaseIterable, Identifiable {
    case amountOff
    case percentOff
    case freeBath
    case manual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .amountOff:
            AppLocalization.localized("loyalty2.settings.kind.amount", value: "Amount off")
        case .percentOff:
            AppLocalization.localized("loyalty2.settings.kind.percent", value: "Percent off")
        case .freeBath:
            AppLocalization.localized("loyalty2.settings.kind.bath", value: "Free Bath")
        case .manual:
            AppLocalization.localized("loyalty2.settings.kind.manual", value: "Applied by hand")
        }
    }

    func benefit(value: Int) -> LoyaltyReward.Benefit {
        switch self {
        case .amountOff: .amountOff(Decimal(max(1, value)))
        case .percentOff: .percentOff(Decimal(min(100, max(1, value))))
        case .freeBath: .freeBath
        case .manual: .manual
        }
    }
}

extension LoyaltyReward.Style: CaseIterable {
    static var allCases: [LoyaltyReward.Style] {
        [.credit, .care, .upgrade, .vip]
    }
}

private extension LoyaltyEarnMode {
    var displayTitle: String {
        switch self {
        case .pointsPerDollar:
            AppLocalization.localized("loyalty.settings.mode.per_dollar", value: "Points per dollar")
        case .flatPerVisit:
            AppLocalization.localized("loyalty.settings.mode.flat", value: "Flat per visit")
        }
    }
}

private extension LoyaltyReward.Style {
    var displayTitle: String {
        switch self {
        case .credit:
            AppLocalization.localized("loyalty.style.credit", value: "Credit")
        case .care:
            AppLocalization.localized("loyalty.style.care", value: "Care")
        case .upgrade:
            AppLocalization.localized("loyalty.style.upgrade", value: "Upgrade")
        case .vip:
            AppLocalization.localized("loyalty.style.vip", value: "VIP")
        }
    }

    var systemImage: String {
        switch self {
        case .credit:
            "ticket.fill"
        case .care:
            "drop.fill"
        case .upgrade:
            "scissors"
        case .vip:
            "sparkles"
        }
    }
}
