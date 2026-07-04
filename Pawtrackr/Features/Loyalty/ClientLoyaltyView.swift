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
    @State private var sheetDestination: SheetDestination?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                balanceCard
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
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "crown.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(DS.ColorToken.warning.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(client.fullName)
                            .font(.headline)
                        Text("Premium loyalty balance")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 12)

                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(client.loyaltyPoints)")
                            .font(.system(.largeTitle, design: .rounded).weight(.black))
                            .contentTransition(.numericText(value: Double(client.loyaltyPoints)))
                        Text("points")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
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
        .accessibilityLabel("\(client.fullName), \(client.loyaltyPoints) loyalty points")
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
                Text("\(loyaltyVisits.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 3)
                    .padding(.horizontal, 7)
                    .background(Capsule().fill(Color.gray.opacity(0.14)))
            }
            .padding(.horizontal)

            if loyaltyVisits.isEmpty {
                ContentUnavailableView(
                    "No Loyalty History",
                    systemImage: "clock.arrow.2.circlepath",
                    description: Text("Completed visits with earned points will appear here.")
                )
                .padding(.vertical, 28)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(loyaltyVisits) { visit in
                        LoyaltyLedgerVisitRow(visit: visit)
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.bottom, 24)
    }

    private var loyaltyVisits: [Visit] {
        (client.pets ?? [])
            .flatMap { $0.visits ?? [] }
            .filter { $0.loyaltyPointsChange != 0 }
            .sorted { $0.sortKeyDate > $1.sortKeyDate }
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

private struct LoyaltyLedgerVisitRow: View {
    let visit: Visit

    var body: some View {
        Card(cornerRadius: 14, padding: EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12), elevation: .regular) {
            HStack(spacing: 12) {
                Image(systemName: visit.loyaltyPointsChange >= 0 ? "plus.circle.fill" : "minus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(visit.loyaltyPointsChange >= 0 ? DS.ColorToken.success : DS.ColorToken.danger)
                    .frame(width: 34, height: 34)
                    .background((visit.loyaltyPointsChange >= 0 ? DS.ColorToken.success : DS.ColorToken.danger).opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(visit.pet?.name ?? "Visit")
                        .font(.subheadline.weight(.semibold))
                    HStack(spacing: 6) {
                        Text(Formatters.dateOnly.string(from: visit.sortKeyDate))
                        if visit.total > .zero {
                            Text("•")
                            Text(Formatters.currencyString(visit.total))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Text(pointsText)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(visit.loyaltyPointsChange >= 0 ? DS.ColorToken.success : DS.ColorToken.danger)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var pointsText: String {
        if visit.loyaltyPointsChange > 0 {
            return "+\(visit.loyaltyPointsChange)"
        }
        return "\(visit.loyaltyPointsChange)"
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
