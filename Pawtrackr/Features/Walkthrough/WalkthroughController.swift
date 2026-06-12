//
//  WalkthroughController.swift
//  Pawtrackr
//
//  Drives the interactive, step-by-step product tour shown to new users on top
//  of the demo-seeded app. Each step spotlights one real control and explains
//  what to do, what it does, and why it helps.
//

import SwiftUI

/// Identifies an interface element the guided tour can spotlight. A control opts
/// in by attaching `.walkthroughAnchor(.someCase)`; the overlay resolves its live
/// on-screen frame at render time. Adding a case here is harmless until a step
/// references it.
enum WalkthroughAnchorID: String, CaseIterable, Hashable {
    case checkIn
    case newClient
    case checkOut
    case reports
}

/// The shape of the spotlight cutout around a target.
enum SpotlightShape: Equatable {
    case circle
    case roundedRect(cornerRadius: CGFloat)
}

/// One coaching stop. Three plain-language fields keep every bubble consistent:
/// the directive (what to tap), and the purpose (what it does / how it helps).
struct WalkthroughStep: Identifiable, Equatable {
    let id: Int
    let anchor: WalkthroughAnchorID
    /// Short headline, e.g. "Check a pet in".
    let title: String
    /// The action to take, e.g. "Tap here when a pet arrives."
    let directive: String
    /// The benefit, e.g. "Starts a secure timer that tracks the exact visit length."
    let purpose: String
    /// SF Symbol shown in the bubble header.
    var icon: String = "hand.tap.fill"
    var shape: SpotlightShape = .roundedRect(cornerRadius: 16)
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
        withAnimation(.easeInOut(duration: 0.3)) { isActive = true }
    }

    /// Advances to the next step, or finishes after the last one.
    func advance() {
        guard isActive else { return }
        if isLastStep {
            finish()
        } else {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                currentIndex += 1
            }
        }
    }

    /// Ends the tour early.
    func skip() { finish() }

    private func finish() {
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
    /// The first tour a new user sees, spotlighting the dashboard's primary
    /// destinations. Copy leads with the action and follows with the payoff.
    static func dashboardTour() -> [WalkthroughStep] {
        [
            WalkthroughStep(
                id: 0,
                anchor: .checkIn,
                title: NSLocalizedString("tour.checkin.title", value: "Check a pet in", comment: ""),
                directive: NSLocalizedString("tour.checkin.directive", value: "Tap Quick Check-In when a pet arrives.", comment: ""),
                purpose: NSLocalizedString("tour.checkin.purpose", value: "It starts a secure timer for the visit, so the exact appointment length is tracked automatically — no spreadsheets, accurate staff time every time.", comment: ""),
                icon: "play.circle.fill"
            ),
            WalkthroughStep(
                id: 1,
                anchor: .newClient,
                title: NSLocalizedString("tour.newclient.title", value: "Add a client", comment: ""),
                directive: NSLocalizedString("tour.newclient.directive", value: "Tap New Client to add an owner and pet.", comment: ""),
                purpose: NSLocalizedString("tour.newclient.purpose", value: "Breed, notes, and behavior are saved with each pet. Mark one “aggressive” and the whole team sees a red warning before they handle it — safety first.", comment: ""),
                icon: "person.crop.circle.badge.plus"
            ),
            WalkthroughStep(
                id: 2,
                anchor: .checkOut,
                title: NSLocalizedString("tour.checkout.title", value: "Check out & get paid", comment: ""),
                directive: NSLocalizedString("tour.checkout.directive", value: "Tap Check-Out to finish a visit.", comment: ""),
                purpose: NSLocalizedString("tour.checkout.purpose", value: "Pick the services, take payment, and you're done in a few taps — every sale flows straight into your daily totals.", comment: ""),
                icon: "stop.circle"
            ),
            WalkthroughStep(
                id: 3,
                anchor: .reports,
                title: NSLocalizedString("tour.reports.title", value: "See your numbers", comment: ""),
                directive: NSLocalizedString("tour.reports.directive", value: "Open Reports anytime.", comment: ""),
                purpose: NSLocalizedString("tour.reports.purpose", value: "Revenue, your most-popular services, and client loyalty are charted for you. When you're ready for real data, clear this demo with “Wipe & Start Fresh” in Settings.", comment: ""),
                icon: "chart.bar.fill"
            )
        ]
    }
}
