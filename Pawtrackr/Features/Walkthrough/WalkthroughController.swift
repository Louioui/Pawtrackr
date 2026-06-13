//
//  WalkthroughController.swift
//  Pawtrackr
//
//  Drives the interactive, step-by-step product tour shown to new users on top
//  of the demo-seeded app. Each step spotlights one real navigation destination
//  (sidebar row on Mac/iPad, tab-bar slot on iPhone) and explains what it is and
//  why it helps.
//

import SwiftUI

/// Identifies an interface element the guided tour can spotlight. A control opts
/// in by attaching `.walkthroughAnchor(.someCase)`; the overlay resolves its live
/// on-screen frame at render time. Tab-bar items (iPhone) can't be anchored in
/// SwiftUI, so those steps fall back to a computed rect — see `SpotlightFallback`.
enum WalkthroughAnchorID: String, CaseIterable, Hashable {
    case dashboard
    case clients
    case insights
    case settings
}

/// The shape of the spotlight cutout around a target.
enum SpotlightShape: Equatable {
    case circle
    case roundedRect(cornerRadius: CGFloat)
}

/// Where to spotlight when no live anchor is registered for a step. SwiftUI does
/// not expose `TabView` tab-item frames, so on iPhone we approximate the bottom
/// tab-bar slot. On Mac/iPad the sidebar rows are real anchors and this is unused.
enum SpotlightFallback: Equatable {
    case none
    /// The `index`-th slot of a bottom tab bar with `count` evenly-spaced items.
    case tabBarItem(index: Int, count: Int)
}

/// One coaching stop. Plain-language fields keep every bubble consistent: the
/// directive (what it is / what to tap) and the purpose (why it helps).
struct WalkthroughStep: Identifiable, Equatable {
    let id: Int
    let anchor: WalkthroughAnchorID
    /// Short headline, e.g. "Clients & Pets".
    let title: String
    /// The action / orientation line, e.g. "Tap Clients to see everyone you groom."
    let directive: String
    /// The benefit, e.g. "Aggressive pets show a red warning so your team stays safe."
    let purpose: String
    /// SF Symbol shown in the bubble header.
    var icon: String = "hand.tap.fill"
    var shape: SpotlightShape = .roundedRect(cornerRadius: 12)
    /// Spotlight target when `anchor` isn't registered live (iPhone tab bar).
    var fallback: SpotlightFallback = .none
}

/// Owns tour state. Intentionally UI-framework-light so it can be created once and
/// handed to the overlay. Driven exclusively by SwiftUI on the main thread; the
/// host gates *whether* to start (e.g. only when the app tour hasn't been seen)
/// and persists "seen" via `onFinish`.
@Observable
final class WalkthroughController {
    private(set) var steps: [WalkthroughStep] = []
    private(set) var currentIndex: Int = 0
    private(set) var isActive: Bool = false

    /// Invoked exactly once when the tour ends — whether the user finished or
    /// skipped. The host persists the "tour seen" flag here so it never auto-shows
    /// again.
    var onFinish: (() -> Void)?

    var currentStep: WalkthroughStep? {
        guard isActive, steps.indices.contains(currentIndex) else { return nil }
        return steps[currentIndex]
    }

    var stepNumber: Int { currentIndex + 1 }
    var stepCount: Int { steps.count }
    var isLastStep: Bool { currentIndex >= steps.count - 1 }

    /// Begins the tour with the given ordered steps. No-op if already running or
    /// the list is empty.
    func start(_ steps: [WalkthroughStep]) {
        guard !isActive, !steps.isEmpty else { return }
        self.steps = steps
        currentIndex = 0
        #if os(iOS)
        HapticManager.impact(.medium)
        #endif
        withAnimation(.easeInOut(duration: 0.3)) { isActive = true }
    }

    /// Advances to the next step, or finishes after the last one.
    func advance() {
        guard isActive else { return }
        #if os(iOS)
        HapticManager.impact(.light)
        #endif
        if isLastStep {
            finish(completed: true)
        } else {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                currentIndex += 1
            }
        }
    }

    /// Ends the tour early.
    func skip() { finish(completed: false) }

    private func finish(completed: Bool) {
        #if os(iOS)
        HapticManager.notify(completed ? .success : .warning)
        #endif
        withAnimation(.easeOut(duration: 0.25)) { isActive = false }
        let handler = onFinish
        onFinish = nil
        steps = []
        currentIndex = 0
        handler?()
    }
}

// MARK: - Default flows

extension WalkthroughController {
    /// The first tour a new user sees: the four primary destinations, spotlighted
    /// in the real navigation chrome — the sidebar rows on Mac/iPad and the bottom
    /// tab bar on iPhone.
    static func navTour() -> [WalkthroughStep] {
        [
            WalkthroughStep(
                id: 0,
                anchor: .dashboard,
                title: NSLocalizedString("tour.nav.dashboard.title", value: "Your Dashboard", comment: ""),
                directive: NSLocalizedString("tour.nav.dashboard.directive", value: "This is your home base.", comment: ""),
                purpose: NSLocalizedString("tour.nav.dashboard.purpose", value: "In-progress visits and today's revenue at a glance — tap a card to jump straight into the work.", comment: ""),
                icon: "square.grid.2x2.fill",
                fallback: .tabBarItem(index: 0, count: 4)
            ),
            WalkthroughStep(
                id: 1,
                anchor: .clients,
                title: NSLocalizedString("tour.nav.clients.title", value: "Clients & Pets", comment: ""),
                directive: NSLocalizedString("tour.nav.clients.directive", value: "Open Clients to see everyone you groom.", comment: ""),
                purpose: NSLocalizedString("tour.nav.clients.purpose", value: "Owners, pets, breeds, and full visit history live here. Aggressive pets show a red warning so your team handles them with care.", comment: ""),
                icon: "person.3.fill",
                fallback: .tabBarItem(index: 1, count: 4)
            ),
            WalkthroughStep(
                id: 2,
                anchor: .insights,
                title: NSLocalizedString("tour.nav.insights.title", value: "Insights", comment: ""),
                directive: NSLocalizedString("tour.nav.insights.directive", value: "Open Insights for your numbers.", comment: ""),
                purpose: NSLocalizedString("tour.nav.insights.purpose", value: "Revenue, your top services, and which pets are overdue — all charted for you, no spreadsheets.", comment: ""),
                icon: "chart.bar.fill",
                fallback: .tabBarItem(index: 2, count: 4)
            ),
            WalkthroughStep(
                id: 3,
                anchor: .settings,
                title: NSLocalizedString("tour.nav.settings.title", value: "Settings & Start Fresh", comment: ""),
                directive: NSLocalizedString("tour.nav.settings.directive", value: "Settings is where you finish setup.", comment: ""),
                purpose: NSLocalizedString("tour.nav.settings.purpose", value: "Tune your services, prices, lock, and iCloud sync. When you're done exploring, “Wipe & Start Fresh” clears the demo for your real business.", comment: ""),
                icon: "gearshape.fill",
                fallback: .tabBarItem(index: 3, count: 4)
            )
        ]
    }
}
