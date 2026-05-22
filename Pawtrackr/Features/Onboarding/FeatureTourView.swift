//
//  FeatureTourView.swift
//  Pawtrackr
//
//  Post-onboarding walkthrough that introduces a new user to the four
//  primary surfaces (Dashboard, Clients, Insights, Settings) before they
//  start using the app.
//

import SwiftUI

struct FeatureTourView: View {
    /// Called when the tour is finished or skipped. The caller should set
    /// `appSettings.hasSeenAppTour = true` on either path.
    var onFinish: () -> Void

    @State private var currentStep: Int = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let steps: [TourStep] = [
        TourStep(
            symbol: "square.grid.2x2.fill",
            tint: .blue,
            title: "Your Dashboard",
            body: "See in-progress visits and revenue at a glance. Tap a card to jump straight into the work.",
            primaryHint: "Tap the Dashboard tab"
        ),
        TourStep(
            symbol: "person.2.fill",
            tint: .purple,
            title: "Clients & Pets",
            body: "Add new clients, manage their pets, and review every visit's history. Use search to find anyone in seconds.",
            primaryHint: "Add your first client from the Clients tab"
        ),
        TourStep(
            symbol: "chart.bar.fill",
            tint: .green,
            title: "Insights",
            body: "Track revenue, see which services drive your business, and spot pets that are overdue for a visit.",
            primaryHint: "Open Insights to view trends"
        ),
        TourStep(
            symbol: "gearshape.fill",
            tint: .orange,
            title: "Settings & Sync",
            body: "Tune your services, currency, lock screen, and iCloud sync. You can re-run this tour any time from Settings.",
            primaryHint: "Settings is on the right of the tab bar"
        )
    ]

    var body: some View {
        ZStack {
            DS.ColorToken.background.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                stepCarousel
                bottomBar
            }
        }
        .accessibilityIdentifier("featureTour.root")
    }

    // MARK: - Sections

    private var topBar: some View {
        HStack {
            stepDots
            Spacer()
            Button("Skip") { finish(skipped: true) }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("featureTour.skip")
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.top, DS.Spacing.md)
    }

    private var stepDots: some View {
        HStack(spacing: 6) {
            ForEach(steps.indices, id: \.self) { idx in
                Capsule()
                    .fill(idx == currentStep ? DS.ColorToken.primary : DS.ColorToken.border)
                    .frame(width: idx == currentStep ? 18 : 6, height: 6)
                    .animation(MotionSystem.snappy, value: currentStep)
            }
        }
        .accessibilityHidden(true)
    }

    private var stepCarousel: some View {
        TabView(selection: $currentStep) {
            ForEach(Array(steps.enumerated()), id: \.offset) { idx, step in
                stepCard(step)
                    .tag(idx)
                    .padding(.horizontal, DS.Spacing.xl)
            }
        }
        #if os(iOS)
        .tabViewStyle(.page(indexDisplayMode: .never))
        #endif
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func stepCard(_ step: TourStep) -> some View {
        VStack(spacing: DS.Spacing.lg) {
            Spacer(minLength: 0)
            ZStack {
                Circle()
                    .fill(step.tint.opacity(0.12))
                    .frame(width: 132, height: 132)
                Image(systemName: step.symbol)
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(step.tint)
                    .symbolRenderingMode(.hierarchical)
            }
            .accessibilityHidden(true)

            Text(step.title)
                .font(.title.weight(.bold))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            Text(step.body)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DS.Spacing.md)

            HStack(spacing: 8) {
                Image(systemName: "hand.point.up.left.fill")
                    .foregroundStyle(step.tint)
                Text(step.primaryHint)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
            .background(
                Capsule().fill(step.tint.opacity(0.10))
            )

            Spacer(minLength: 0)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: DS.Spacing.md) {
            if currentStep > 0 {
                Button {
                    withAnimation(MotionSystem.snappy) { currentStep -= 1 }
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .labelStyle(.titleAndIcon)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Spacing.md)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("featureTour.back")
            }

            Button {
                advance()
            } label: {
                Text(currentStep == steps.count - 1 ? "Get Started" : "Next")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Spacing.md)
            }
            .buttonStyle(.borderedProminent)
            .tint(DS.ColorToken.primary)
            .accessibilityIdentifier("featureTour.next")
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.bottom, DS.Spacing.lg)
    }

    // MARK: - Actions

    private func advance() {
        if currentStep < steps.count - 1 {
            withAnimation(MotionSystem.snappy) { currentStep += 1 }
        } else {
            finish(skipped: false)
        }
    }

    private func finish(skipped: Bool) {
        #if os(iOS)
        HapticManager.notify(skipped ? .warning : .success)
        #endif
        onFinish()
    }
}

private struct TourStep: Identifiable {
    let id = UUID()
    let symbol: String
    let tint: Color
    let title: String
    let body: String
    let primaryHint: String
}

#Preview {
    FeatureTourView { }
}
