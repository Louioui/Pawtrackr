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
            DataMigrations.ensureLoyaltyDefaults(in: modelContext)
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
                    Text("Pawtrackr Pro")
                        .font(.headline)
                    Text("Loyalty configuration is available with active Pro access.")
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
                Label("Loyalty Earning Rules", systemImage: "star.circle.fill")
                    .font(.headline)

                Picker("Earning Mode", selection: earnModeBinding) {
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
                            title: "Points per dollar",
                            value: "\(pointsPerDollarBinding.wrappedValue)"
                        )
                    }
                    .accessibilityIdentifier("loyaltySettings.pointsPerDollar")
                case .flatPerVisit:
                    Stepper(value: pointsPerVisitBinding, in: 0...500, step: 5) {
                        settingsValueRow(
                            title: "Flat visit points",
                            value: "\(pointsPerVisitBinding.wrappedValue)"
                        )
                    }
                    .accessibilityIdentifier("loyaltySettings.pointsPerVisit")
                }

                Stepper(value: thresholdBinding, in: 1...10_000, step: 25) {
                    settingsValueRow(
                        title: "Reward threshold",
                        value: "\(thresholdBinding.wrappedValue)"
                    )
                }
                .accessibilityIdentifier("loyaltySettings.redemptionThreshold")

                Toggle(isOn: catalogEnabledBinding) {
                    Label("Rewards Catalog", systemImage: "gift.fill")
                }
                .accessibilityIdentifier("loyaltySettings.catalogEnabled")
            }
        }
    }

    private var rewardsCatalogCard: some View {
        Card(cornerRadius: 12, accent: .leading(.color(DS.ColorToken.info))) {
            VStack(alignment: .leading, spacing: 14) {
                Label("Reward Templates", systemImage: "giftcard.fill")
                    .font(.headline)

                if rewards.isEmpty {
                    ContentUnavailableView(
                        "No Rewards",
                        systemImage: "gift",
                        description: Text("Default rewards are added on launch.")
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
            TextField("Reward title", text: $newRewardTitle)
                .textFieldStyle(.roundedBorder)
                .textLengthLimit($newRewardTitle, to: TextInputLimits.name)
                .accessibilityIdentifier("loyaltySettings.newRewardTitle")

            TextField("Reward detail", text: $newRewardDetail)
                .textFieldStyle(.roundedBorder)
                .textLengthLimit($newRewardDetail, to: TextInputLimits.notes)
                .accessibilityIdentifier("loyaltySettings.newRewardDetail")

            Stepper(value: $newRewardCost, in: 1...10_000, step: 25) {
                settingsValueRow(title: "Cost", value: "\(newRewardCost) points")
            }
            .accessibilityIdentifier("loyaltySettings.newRewardCost")

            Picker("Style", selection: $newRewardStyle) {
                ForEach(LoyaltyReward.Style.allCases, id: \.self) { style in
                    Label(style.displayTitle, systemImage: style.systemImage)
                        .tag(style)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("loyaltySettings.newRewardStyle")

            Button {
                createReward()
            } label: {
                Label("Add Reward", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
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
                    Text(reward.title)
                        .font(.subheadline.weight(.semibold))
                    Text("\(reward.pointCost) points")
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
                earnMode: earnMode ?? config?.earnMode ?? .pointsPerDollar,
                pointsPerDollar: pointsPerDollar ?? config?.pointsPerDollar ?? Decimal(1),
                pointsPerVisit: pointsPerVisit ?? config?.pointsPerVisit ?? 20,
                redemptionThreshold: redemptionThreshold ?? config?.redemptionThreshold ?? 100,
                isRewardsCatalogEnabled: isRewardsCatalogEnabled ?? config?.isRewardsCatalogEnabled ?? true
            )
        }
    }

    private func createReward() {
        let title = newRewardTitle
        let detail = newRewardDetail.isEmpty ? "Custom loyalty reward." : newRewardDetail
        let cost = newRewardCost
        let style = newRewardStyle

        mutate { service in
            try await service.createRewardTemplate(
                title: title,
                detail: detail,
                pointCost: cost,
                systemImage: style.systemImage,
                style: style
            )
            newRewardTitle = ""
            newRewardDetail = ""
            newRewardCost = 100
            newRewardStyle = .credit
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

extension LoyaltyReward.Style: CaseIterable {
    static var allCases: [LoyaltyReward.Style] {
        [.credit, .care, .upgrade, .vip]
    }
}

private extension LoyaltyEarnMode {
    var displayTitle: String {
        switch self {
        case .pointsPerDollar:
            "Points per dollar"
        case .flatPerVisit:
            "Flat per visit"
        }
    }
}

private extension LoyaltyReward.Style {
    var displayTitle: String {
        switch self {
        case .credit:
            "Credit"
        case .care:
            "Care"
        case .upgrade:
            "Upgrade"
        case .vip:
            "VIP"
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
