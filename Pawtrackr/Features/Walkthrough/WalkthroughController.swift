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
    // Primary navigation (sidebar rows / tab-bar slots)
    case dashboard
    case clients
    case insights
    case settings
    // Dashboard content sections
    case dashKpis
    case dashQuickActions
    case dashNeedsAttention
    case dashRecentClients
    case dashRevenue
    // Insights content cards
    case insKpis
    case insRevenue
    case insMonthly
    case insServices
    case insPaymentMix
    case insCategory
    // New-client form sections
    case ncOwner
    case ncPets
    case ncSave
    // Settings sections
    case setBusiness
    case setSecurity
    case setData
    case setICloud
    case setAbout
}

/// A modal the deep-dive tour opens to walk through its contents. The host
/// presents/dismisses it as the relevant steps come and go.
enum WalkthroughPresentation: Equatable {
    case newClient
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
    /// Which primary screen this step lives on. The host navigates here before the
    /// step shows, and the screen scrolls `anchor` into view. `nil` for steps whose
    /// target is always on screen (e.g. the nav chrome itself).
    var surface: NavigationItem? = nil
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
    /// A modal this step lives inside. The host opens it before the step shows
    /// and closes it once the steps that need it are done. `nil` = main UI.
    var presents: WalkthroughPresentation? = nil
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
    /// The full guided deep-dive a new user sees: it walks the four primary
    /// screens AND every key section inside the Dashboard and Insights, driving
    /// navigation and scrolling each target into view. Section-level steps keep
    /// the copy rich without an exhausting number of stops.
    static func fullTour() -> [WalkthroughStep] {
        var id = 0
        func next() -> Int { defer { id += 1 }; return id }

        return [
            // MARK: Dashboard
            WalkthroughStep(
                id: next(), anchor: .dashboard, surface: .dashboard,
                title: AppLocalization.localized("tour.nav.dashboard.title", value: "Your Dashboard"),
                directive: AppLocalization.localized("tour.nav.dashboard.directive", value: "This is your home base."),
                purpose: AppLocalization.localized("tour.nav.dashboard.purpose", value: "In-progress visits and today's revenue at a glance — tap a card to jump straight into the work."),
                icon: "square.grid.2x2.fill", fallback: .tabBarItem(index: 0, count: 4)
            ),
            WalkthroughStep(
                id: next(), anchor: .dashKpis, surface: .dashboard,
                title: AppLocalization.localized("tour.dash.kpis.title", value: "Today at a glance"),
                directive: AppLocalization.localized("tour.dash.kpis.directive", value: "Your live numbers for today."),
                purpose: AppLocalization.localized("tour.dash.kpis.purpose", value: "“In Progress” is pets currently being groomed, “Completed” is how many you've finished today, and “Revenue” is what you've earned so far — all updating automatically as you work."),
                icon: "clock.fill"
            ),
            WalkthroughStep(
                id: next(), anchor: .dashQuickActions, surface: .dashboard,
                title: AppLocalization.localized("tour.dash.quick.title", value: "Quick Actions"),
                directive: AppLocalization.localized("tour.dash.quick.directive", value: "One-tap shortcuts."),
                purpose: AppLocalization.localized("tour.dash.quick.purpose", value: "Add a new client, check a pet in (starts the visit timer), check out to take payment, or open Reports — without hunting through menus."),
                icon: "bolt.fill"
            ),
            WalkthroughStep(
                id: next(), anchor: .dashNeedsAttention, surface: .dashboard,
                title: AppLocalization.localized("tour.dash.attention.title", value: "Needs Attention"),
                directive: AppLocalization.localized("tour.dash.attention.directive", value: "Who's overdue for a visit."),
                purpose: AppLocalization.localized("tour.dash.attention.purpose", value: "Pets that are due for their next groom surface here, so you can reach out and rebook them before they drift away."),
                icon: "exclamationmark.circle.fill"
            ),
            WalkthroughStep(
                id: next(), anchor: .dashRecentClients, surface: .dashboard,
                title: AppLocalization.localized("tour.dash.recent.title", value: "Recent Clients"),
                directive: AppLocalization.localized("tour.dash.recent.directive", value: "Pick up where you left off."),
                purpose: AppLocalization.localized("tour.dash.recent.purpose", value: "Your most recent clients for fast rebooking. Tap one to open their full profile — and any aggressive pet is flagged in red so the team stays safe."),
                icon: "person.2.fill"
            ),
            WalkthroughStep(
                id: next(), anchor: .dashRevenue, surface: .dashboard,
                title: AppLocalization.localized("tour.dash.revenue.title", value: "Revenue (7 Days)"),
                directive: AppLocalization.localized("tour.dash.revenue.directive", value: "Your week at a glance."),
                purpose: AppLocalization.localized("tour.dash.revenue.purpose", value: "Every checkout flows into this chart automatically — so you can tell a strong week from a slow one without touching a spreadsheet."),
                icon: "chart.bar.fill"
            ),
            // MARK: Clients
            WalkthroughStep(
                id: next(), anchor: .clients, surface: .clients,
                title: AppLocalization.localized("tour.nav.clients.title", value: "Clients & Pets"),
                directive: AppLocalization.localized("tour.nav.clients.directive", value: "Everyone you groom lives here."),
                purpose: AppLocalization.localized("tour.nav.clients.purpose", value: "Owners, pets, breeds, and full visit history. Use “New Client” to add someone and their pet — set a behavior tag like “aggressive” and the whole team sees a red warning before they handle it."),
                icon: "person.3.fill", fallback: .tabBarItem(index: 1, count: 4)
            ),
            // MARK: Create a client (opens the New Client sheet)
            WalkthroughStep(
                id: next(), anchor: .ncOwner, surface: .clients, presents: .newClient,
                title: AppLocalization.localized("tour.nc.owner.title", value: "Add the owner"),
                directive: AppLocalization.localized("tour.nc.owner.directive", value: "Start with their details."),
                purpose: AppLocalization.localized("tour.nc.owner.purpose", value: "Name, phone, email, and address — phone and email are how you'll reach them to confirm and rebook. Only a name is required; add the rest anytime."),
                icon: "person.text.rectangle"
            ),
            WalkthroughStep(
                id: next(), anchor: .ncPets, surface: .clients, presents: .newClient,
                title: AppLocalization.localized("tour.nc.pets.title", value: "Add their pets"),
                directive: AppLocalization.localized("tour.nc.pets.directive", value: "One client, many pets."),
                purpose: AppLocalization.localized("tour.nc.pets.purpose", value: "Add each pet's name, species, breed, and gender. Tag behavior like “aggressive” here and the whole team gets a red warning before they ever handle the pet — safety first."),
                icon: "pawprint.fill"
            ),
            WalkthroughStep(
                id: next(), anchor: .ncSave, surface: .clients, presents: .newClient,
                title: AppLocalization.localized("tour.nc.save.title", value: "Save the client"),
                directive: AppLocalization.localized("tour.nc.save.directive", value: "That's it — tap Save."),
                purpose: AppLocalization.localized("tour.nc.save.purpose", value: "They're added instantly and ready to check in. We'll close this without saving so you can keep exploring."),
                icon: "checkmark.circle.fill"
            ),
            // MARK: Insights
            WalkthroughStep(
                id: next(), anchor: .insights, surface: .insights,
                title: AppLocalization.localized("tour.nav.insights.title", value: "Insights"),
                directive: AppLocalization.localized("tour.nav.insights.directive", value: "Your numbers, charted for you."),
                purpose: AppLocalization.localized("tour.nav.insights.purpose", value: "Revenue, top services, payment mix and more — all calculated automatically. Let's look at each piece."),
                icon: "chart.bar.fill", fallback: .tabBarItem(index: 2, count: 4)
            ),
            WalkthroughStep(
                id: next(), anchor: .insKpis, surface: .insights,
                title: AppLocalization.localized("tour.ins.kpis.title", value: "Headline numbers"),
                directive: AppLocalization.localized("tour.ins.kpis.directive", value: "The three that matter most."),
                purpose: AppLocalization.localized("tour.ins.kpis.purpose", value: "Total revenue, what an average visit is worth, and how many clients come back (retention) — your business health in one row."),
                icon: "number"
            ),
            WalkthroughStep(
                id: next(), anchor: .insRevenue, surface: .insights,
                title: AppLocalization.localized("tour.ins.revenue.title", value: "Revenue over time"),
                directive: AppLocalization.localized("tour.ins.revenue.directive", value: "Spot your trend."),
                purpose: AppLocalization.localized("tour.ins.revenue.purpose", value: "Switch between 7, 30, and 90 days to tell a good stretch from a slow one and see where you're heading."),
                icon: "dollarsign.circle.fill"
            ),
            WalkthroughStep(
                id: next(), anchor: .insMonthly, surface: .insights,
                title: AppLocalization.localized("tour.ins.monthly.title", value: "Monthly Performance"),
                directive: AppLocalization.localized("tour.ins.monthly.directive", value: "Month by month."),
                purpose: AppLocalization.localized("tour.ins.monthly.purpose", value: "Compare months to find your busy season and plan staffing and promotions around it."),
                icon: "calendar"
            ),
            WalkthroughStep(
                id: next(), anchor: .insServices, surface: .insights,
                title: AppLocalization.localized("tour.ins.services.title", value: "Service Profitability"),
                directive: AppLocalization.localized("tour.ins.services.directive", value: "What earns the most."),
                purpose: AppLocalization.localized("tour.ins.services.purpose", value: "See which services drive your revenue so you can promote the winners and rethink the rest."),
                icon: "scissors"
            ),
            WalkthroughStep(
                id: next(), anchor: .insPaymentMix, surface: .insights,
                title: AppLocalization.localized("tour.ins.payment.title", value: "Payment Mix"),
                directive: AppLocalization.localized("tour.ins.payment.directive", value: "How clients pay."),
                purpose: AppLocalization.localized("tour.ins.payment.purpose", value: "Cash, card, or transfer — knowing your mix helps you plan deposits and spot processing fees."),
                icon: "creditcard.fill"
            ),
            WalkthroughStep(
                id: next(), anchor: .insCategory, surface: .insights,
                title: AppLocalization.localized("tour.ins.category.title", value: "Visits by Category"),
                directive: AppLocalization.localized("tour.ins.category.directive", value: "Where your time goes."),
                purpose: AppLocalization.localized("tour.ins.category.purpose", value: "A breakdown of grooms, add-ons, and special care so you can see what you do most."),
                icon: "square.grid.2x2"
            ),
            // MARK: Settings
            WalkthroughStep(
                id: next(), anchor: .settings, surface: .settings,
                title: AppLocalization.localized("tour.nav.settings.title", value: "Settings & Start Fresh"),
                directive: AppLocalization.localized("tour.nav.settings.directive", value: "Make the app yours."),
                purpose: AppLocalization.localized("tour.nav.settings.purpose", value: "Tune your services, prices, currency, lock, and iCloud sync here. When you're done exploring, “Wipe & Start Fresh” clears the demo so you can begin with your real business."),
                icon: "gearshape.fill", fallback: .tabBarItem(index: 3, count: 4)
            ),
            WalkthroughStep(
                id: next(), anchor: .setBusiness, surface: .settings,
                title: AppLocalization.localized("tour.set.business.title", value: "Business profile"),
                directive: AppLocalization.localized("tour.set.business.directive", value: "Your name and brand."),
                purpose: AppLocalization.localized("tour.set.business.purpose", value: "Set your business name, logo, and brand color — they appear on receipts and reports. Preferences nearby control haptics, language, theme, and your default opening tab."),
                icon: "building.2.fill"
            ),
            WalkthroughStep(
                id: next(), anchor: .setSecurity, surface: .settings,
                title: AppLocalization.localized("tour.set.security.title", value: "Security"),
                directive: AppLocalization.localized("tour.set.security.directive", value: "Lock down client data."),
                purpose: AppLocalization.localized("tour.set.security.purpose", value: "Turn on App Lock (you'll choose a PIN), add Face ID / Touch ID, auto-lock when the app closes or after idle time, and change your PIN — all here."),
                icon: "lock.shield.fill"
            ),
            WalkthroughStep(
                id: next(), anchor: .setData, surface: .settings,
                title: AppLocalization.localized("tour.set.data.title", value: "Export your data"),
                directive: AppLocalization.localized("tour.set.data.directive", value: "It's yours to take."),
                purpose: AppLocalization.localized("tour.set.data.purpose", value: "Export clients and visits to CSV anytime — for your accountant, a backup, or moving between devices."),
                icon: "square.and.arrow.up"
            ),
            WalkthroughStep(
                id: next(), anchor: .setICloud, surface: .settings,
                title: AppLocalization.localized("tour.set.icloud.title", value: "iCloud sync"),
                directive: AppLocalization.localized("tour.set.icloud.directive", value: "Same data, every device."),
                purpose: AppLocalization.localized("tour.set.icloud.purpose", value: "Sign in to iCloud and your clients, pets, and visits sync automatically across iPhone, iPad, and Mac — and back up safely. Run diagnostics here if sync ever looks off."),
                icon: "icloud.fill"
            ),
            WalkthroughStep(
                id: next(), anchor: .setAbout, surface: .settings,
                title: AppLocalization.localized("tour.set.about.title", value: "Replay & Start Fresh"),
                directive: AppLocalization.localized("tour.set.about.directive", value: "This tour lives here too."),
                purpose: AppLocalization.localized("tour.set.about.purpose", value: "Replay this walkthrough anytime, and when you're ready to drop the demo, “Wipe & Start Fresh” clears the sample data so you can begin with your real business."),
                icon: "sparkles"
            )
        ]
    }
}
