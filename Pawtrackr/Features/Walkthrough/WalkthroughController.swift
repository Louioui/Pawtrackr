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
import SwiftData

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
    // Client-detail sections
    case cdOwner
    case cdEmergency
    case cdPets
    case cdAddPet
    case cdCheckIn
    case cdCheckOut
    case cdPetHistory
    case cdHistory
    // Checkout flow sections
    case coServices
    case coDetails
    case coPayment
    case coReview
    case coConfirm
    // Settings sections
    case setBusiness
    case setSecurity
    case setData
    case setICloud
    case setAbout
    case setStartFresh
}

/// A modal the deep-dive tour opens to walk through its contents. The host
/// presents/dismisses it as the relevant steps come and go.
enum WalkthroughPresentation: Equatable {
    case newClient
    case checkout
}

/// A real in-app route the walkthrough can open before showing a step.
enum WalkthroughRoute: Equatable {
    case demoClientDetail
}

/// High-level curriculum buckets shown in every walkthrough bubble. The tour is
/// long on purpose, so labels help new users understand where they are in the
/// learning path instead of reading each step as an isolated tooltip.
enum WalkthroughLesson: String, CaseIterable, Hashable {
    case appMap
    case dailyWorkflow
    case clientRecords
    case checkoutAndMoney
    case businessInsights
    case settingsAndSafety
    case dataOwnership

    var title: String {
        switch self {
        case .appMap:
            return AppLocalization.localized("tour.lesson.app_map", value: "App Map")
        case .dailyWorkflow:
            return AppLocalization.localized("tour.lesson.daily_workflow", value: "Daily Workflow")
        case .clientRecords:
            return AppLocalization.localized("tour.lesson.client_records", value: "Client Records")
        case .checkoutAndMoney:
            return AppLocalization.localized("tour.lesson.checkout_money", value: "Checkout & Money")
        case .businessInsights:
            return AppLocalization.localized("tour.lesson.insights", value: "Business Insights")
        case .settingsAndSafety:
            return AppLocalization.localized("tour.lesson.settings_safety", value: "Settings & Safety")
        case .dataOwnership:
            return AppLocalization.localized("tour.lesson.data_ownership", value: "Data Ownership")
        }
    }

    var icon: String {
        switch self {
        case .appMap: return "map.fill"
        case .dailyWorkflow: return "arrow.triangle.2.circlepath"
        case .clientRecords: return "person.text.rectangle.fill"
        case .checkoutAndMoney: return "creditcard.fill"
        case .businessInsights: return "chart.xyaxis.line"
        case .settingsAndSafety: return "lock.shield.fill"
        case .dataOwnership: return "externaldrive.fill"
        }
    }
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
    /// Top-trailing action in a navigation bar or full-screen cover toolbar.
    case topTrailingAction
    /// Bottom-trailing confirmation action in a macOS sheet footer.
    case bottomTrailingAction
    /// A single compact top-trailing icon button (e.g. a macOS toolbar "+"),
    /// narrower than `.topTrailingAction` so the spotlight lands on just that
    /// control and not a neighbor (like an adjacent delete button).
    case topTrailingIcon
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
    /// Optional deeper navigation inside a primary screen.
    var route: WalkthroughRoute? = nil
    /// Short headline, e.g. "Clients & Pets".
    let title: String
    /// The action / orientation line, e.g. "Tap Clients to see everyone you groom."
    let directive: String
    /// The benefit, e.g. "Aggressive pets show a red warning so your team stays safe."
    let purpose: String
    /// Learning category for this step.
    var lesson: WalkthroughLesson = .appMap
    /// Small practical hint shown below the main explanation.
    var coachTip: String? = nil
    /// SF Symbol shown in the bubble header.
    var icon: String = "hand.tap.fill"
    var shape: SpotlightShape = .roundedRect(cornerRadius: 12)
    /// Spotlight target when `anchor` isn't registered live (iPhone tab bar).
    var fallback: SpotlightFallback = .none
    /// A modal this step lives inside. The host opens it before the step shows
    /// and closes it once the steps that need it are done. `nil` = main UI.
    var presents: WalkthroughPresentation? = nil
    /// Whether the highlighted UI should remain usable. Form and save steps use
    /// this so the walkthrough can teach a real workflow instead of intercepting
    /// the user's tap.
    var allowsTargetInteraction = false
    /// Whether the bubble's Next button should pause until the user taps the
    /// highlighted control. Used for handoffs that must execute real app state.
    var requiresTargetAction = false
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
    private(set) var preferredClientDetailID: PersistentIdentifier?

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
    /// Whether an earlier step exists to return to. Drives the Back control so a
    /// user who advanced too quickly can step back and re-read what they missed.
    var canGoBack: Bool { isActive && currentIndex > 0 }

    /// Begins the tour with the given ordered steps. No-op if already running or
    /// the list is empty.
    func start(_ steps: [WalkthroughStep]) {
        guard !isActive, !steps.isEmpty else { return }
        self.steps = steps
        currentIndex = 0
        preferredClientDetailID = nil
        #if os(iOS)
        HapticManager.impact(.medium)
        #endif
        withAnimation(.easeInOut(duration: 0.3)) { isActive = true }
    }

    /// Replays the tour from the beginning even if a previous run is active or
    /// the "seen" flag has already been cleared. Used by Settings so replay is
    /// an explicit command instead of depending only on a UserDefaults edge.
    func restart(_ steps: [WalkthroughStep]) {
        guard !steps.isEmpty else { return }
        self.steps = steps
        currentIndex = 0
        preferredClientDetailID = nil
        #if os(iOS)
        HapticManager.impact(.medium)
        #endif
        withAnimation(.easeInOut(duration: 0.3)) { isActive = true }
    }

    func focusClientDetail(_ clientID: PersistentIdentifier) {
        preferredClientDetailID = clientID
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

    /// Returns to the previous step so a user who moved too fast can re-read what
    /// they missed. Navigation, sheets, and scrolling re-drive symmetrically off
    /// the host's `surface`/`route`/`presents`/`anchor` onChange handlers, so a
    /// simple index decrement is enough to reverse the tour.
    func goBack() {
        guard isActive, currentIndex > 0 else { return }
        #if os(iOS)
        HapticManager.impact(.light)
        #endif
        withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
            currentIndex -= 1
        }
    }

    /// Moves past the current modal-backed lesson when the user completes the
    /// real modal action, e.g. creating a client from the New Client sheet.
    func completePresentation(_ presentation: WalkthroughPresentation) {
        guard isActive, currentStep?.presents == presentation else { return }
        #if os(iOS)
        HapticManager.impact(.light)
        #endif

        let remainingIndices = steps.indices.drop(while: { $0 <= currentIndex })
        guard let nextIndex = remainingIndices.first(where: { steps[$0].presents != presentation }) else {
            finish(completed: true)
            return
        }

        withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
            currentIndex = nextIndex
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
        preferredClientDetailID = nil
        handler?()
    }
}

// MARK: - Default flows

extension WalkthroughController {
    /// The add-pet control differs by platform: iPhone and iPad show a circular
    /// paw FAB that anchors directly, while Mac shows a compact "+" toolbar button
    /// that SwiftUI won't anchor — so it falls back to a narrow top-trailing rect.
    static var addPetSpotlightShape: SpotlightShape {
        #if os(iOS)
        .circle
        #else
        .roundedRect(cornerRadius: 10)
        #endif
    }

    static var addPetSpotlightFallback: SpotlightFallback {
        #if os(iOS)
        .none
        #else
        .topTrailingIcon
        #endif
    }

    /// The New Client confirmation action is top-trailing in iOS full-screen
    /// covers, but bottom-trailing in the macOS sheet footer.
    static var newClientSaveSpotlightFallback: SpotlightFallback {
        #if os(iOS)
        .topTrailingAction
        #else
        .bottomTrailingAction
        #endif
    }

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
                directive: AppLocalization.localized("tour.nav.dashboard.directive", value: "Start every day here."),
                purpose: AppLocalization.localized("tour.nav.dashboard.purpose", value: "Dashboard is the command center: active visits, today’s revenue, shortcuts, reminders, and recent clients all land in one place."),
                lesson: .appMap,
                coachTip: AppLocalization.localized("tour.nav.dashboard.tip", value: "The app loop is simple: find the client, check in the pet, finish checkout, then review the numbers."),
                icon: "square.grid.2x2.fill", fallback: .tabBarItem(index: 0, count: 4)
            ),
            WalkthroughStep(
                id: next(), anchor: .dashKpis, surface: .dashboard,
                title: AppLocalization.localized("tour.dash.kpis.title", value: "Today at a glance"),
                directive: AppLocalization.localized("tour.dash.kpis.directive", value: "Read your live day before opening any list."),
                purpose: AppLocalization.localized("tour.dash.kpis.purpose", value: "“In Progress” is pets currently being groomed, “Completed” is how many you have finished today, and “Revenue” is what you have earned so far."),
                lesson: .dailyWorkflow,
                coachTip: AppLocalization.localized("tour.dash.kpis.tip", value: "If a number looks off, Recent History and Insights help you reconcile the visit behind it."),
                icon: "clock.fill"
            ),
            WalkthroughStep(
                id: next(), anchor: .dashQuickActions, surface: .dashboard,
                title: AppLocalization.localized("tour.dash.quick.title", value: "Quick Actions"),
                directive: AppLocalization.localized("tour.dash.quick.directive", value: "Use these when the salon gets busy."),
                purpose: AppLocalization.localized("tour.dash.quick.purpose", value: "Add a new client, check a pet in to start the visit timer, check out to take payment, or open Reports without hunting through menus."),
                lesson: .dailyWorkflow,
                coachTip: AppLocalization.localized("tour.dash.quick.tip", value: "These shortcuts mirror the real front-desk workflow so you can move fast with one hand."),
                icon: "bolt.fill"
            ),
            WalkthroughStep(
                id: next(), anchor: .dashQuickActions, surface: .dashboard,
                title: AppLocalization.localized("tour.workflow.checkout.title", value: "Check-In to Checkout"),
                directive: AppLocalization.localized("tour.workflow.checkout.directive", value: "This is the main working loop."),
                purpose: AppLocalization.localized("tour.workflow.checkout.purpose", value: "Check in starts the timer, the visit collects services, notes, and photos, and checkout records payment, tip, reference, and receipt details for history and reporting."),
                lesson: .checkoutAndMoney,
                coachTip: AppLocalization.localized("tour.workflow.checkout.tip", value: "Money uses exact Decimal calculations, so service totals, tips, and payments stay dependable."),
                icon: "arrow.triangle.2.circlepath"
            ),
            WalkthroughStep(
                id: next(), anchor: .dashNeedsAttention, surface: .dashboard,
                title: AppLocalization.localized("tour.dash.attention.title", value: "Needs Attention"),
                directive: AppLocalization.localized("tour.dash.attention.directive", value: "See who needs a follow-up."),
                purpose: AppLocalization.localized("tour.dash.attention.purpose", value: "Pets due for their next groom surface here, so you can call, message, and rebook them before they drift away."),
                lesson: .dailyWorkflow,
                icon: "exclamationmark.circle.fill"
            ),
            WalkthroughStep(
                id: next(), anchor: .dashRecentClients, surface: .dashboard,
                title: AppLocalization.localized("tour.dash.recent.title", value: "Recent Clients"),
                directive: AppLocalization.localized("tour.dash.recent.directive", value: "Pick up where you left off."),
                purpose: AppLocalization.localized("tour.dash.recent.purpose", value: "Your most recent clients are here for fast rebooking. Tap one to open the full profile, pet history, and safety notes."),
                lesson: .clientRecords,
                coachTip: AppLocalization.localized("tour.dash.recent.tip", value: "Aggressive behavior tags appear in red anywhere the team needs to notice them."),
                icon: "person.2.fill"
            ),
            WalkthroughStep(
                id: next(), anchor: .dashRevenue, surface: .dashboard,
                title: AppLocalization.localized("tour.dash.revenue.title", value: "Revenue (7 Days)"),
                directive: AppLocalization.localized("tour.dash.revenue.directive", value: "Watch the week while you work."),
                purpose: AppLocalization.localized("tour.dash.revenue.purpose", value: "Every completed checkout flows into this chart automatically, so you can tell a strong week from a slow one without touching a spreadsheet."),
                lesson: .checkoutAndMoney,
                icon: "chart.bar.fill"
            ),
            // MARK: Clients
            WalkthroughStep(
                id: next(), anchor: .clients, surface: .clients,
                title: AppLocalization.localized("tour.nav.clients.title", value: "Clients & Pets"),
                directive: AppLocalization.localized("tour.nav.clients.directive", value: "This is your record book."),
                purpose: AppLocalization.localized("tour.nav.clients.purpose", value: "Owners, pets, breeds, photos, health notes, behavior tags, emergency contacts, and full visit history live here."),
                lesson: .clientRecords,
                coachTip: AppLocalization.localized("tour.nav.clients.tip", value: "One client can have many pets, so multi-pet families stay together."),
                icon: "person.3.fill", fallback: .tabBarItem(index: 1, count: 4)
            ),
            // MARK: Create a client (opens the New Client sheet)
            WalkthroughStep(
                id: next(), anchor: .ncOwner, surface: .clients,
                title: AppLocalization.localized("tour.nc.owner.title", value: "Add the owner"),
                directive: AppLocalization.localized("tour.nc.owner.directive", value: "Start with the person who books and pays."),
                purpose: AppLocalization.localized("tour.nc.owner.purpose", value: "Name, phone, email, address, and emergency contacts help you confirm appointments, follow up, and keep the right contact details on receipts and exports."),
                lesson: .clientRecords,
                coachTip: AppLocalization.localized("tour.nc.owner.tip", value: "Only a name is required; add the rest now or fill it in later."),
                icon: "person.text.rectangle",
                presents: .newClient,
                allowsTargetInteraction: true
            ),
            WalkthroughStep(
                id: next(), anchor: .ncPets, surface: .clients,
                title: AppLocalization.localized("tour.nc.pets.title", value: "Add their pets"),
                directive: AppLocalization.localized("tour.nc.pets.directive", value: "Capture the details the team needs before handling."),
                purpose: AppLocalization.localized("tour.nc.pets.purpose", value: "Add each pet’s name, photo, species, breed, color, gender, health notes, grooming preferences, and behavior tags like aggressive for safety."),
                lesson: .clientRecords,
                coachTip: AppLocalization.localized("tour.nc.pets.tip", value: "A good pet profile turns the next visit into a quick check-in instead of a memory test."),
                icon: "pawprint.fill",
                presents: .newClient,
                allowsTargetInteraction: true
            ),
            WalkthroughStep(
                id: next(), anchor: .ncSave, surface: .clients,
                title: AppLocalization.localized("tour.nc.save.title", value: "Save the client"),
                directive: AppLocalization.localized("tour.nc.save.directive", value: "Create once, reuse every visit."),
                purpose: AppLocalization.localized("tour.nc.save.purpose", value: "Tap Create when you are adding a real client, or use Next to keep practicing. Once saved, the client is ready for check in, services, checkout, receipts, and future history."),
                lesson: .clientRecords,
                icon: "checkmark.circle.fill",
                fallback: newClientSaveSpotlightFallback,
                presents: .newClient,
                allowsTargetInteraction: true
            ),
            // MARK: Client details
            WalkthroughStep(
                id: next(), anchor: .cdOwner, surface: .clients, route: .demoClientDetail,
                title: AppLocalization.localized("tour.cd.owner.title", value: "Client Details"),
                directive: AppLocalization.localized("tour.cd.owner.directive", value: "This is the profile you open from the Clients list."),
                purpose: AppLocalization.localized("tour.cd.owner.purpose", value: "The top card keeps the owner’s phone, email, address, messaging, and quick edit actions together so you can confirm details during booking or pickup."),
                lesson: .clientRecords,
                coachTip: AppLocalization.localized("tour.cd.owner.tip", value: "Use this screen before every appointment when you need contact info, pet notes, or history in one place."),
                icon: "person.crop.rectangle.stack.fill"
            ),
            WalkthroughStep(
                id: next(), anchor: .cdEmergency, surface: .clients, route: .demoClientDetail,
                title: AppLocalization.localized("tour.cd.emergency.title", value: "Emergency Contacts"),
                directive: AppLocalization.localized("tour.cd.emergency.directive", value: "Keep backup contacts close."),
                purpose: AppLocalization.localized("tour.cd.emergency.purpose", value: "If the owner cannot answer, emergency contacts give your team another safe way to reach someone responsible for the pet."),
                lesson: .clientRecords,
                icon: "phone.badge.plus"
            ),
            WalkthroughStep(
                id: next(), anchor: .cdPets, surface: .clients, route: .demoClientDetail,
                title: AppLocalization.localized("tour.cd.pets.title", value: "Pet Actions"),
                directive: AppLocalization.localized("tour.cd.pets.directive", value: "This row is where the visit work starts."),
                purpose: AppLocalization.localized("tour.cd.pets.purpose", value: "Each pet has its own status and actions. The next stops break down check-in, checkout, and history so the workflow is clear before you use it with real clients."),
                lesson: .dailyWorkflow,
                coachTip: AppLocalization.localized("tour.cd.pets.tip", value: "Each owner can have multiple pets, and every pet keeps its own status and visit history."),
                icon: "pawprint.fill"
            ),
            WalkthroughStep(
                id: next(), anchor: .cdAddPet, surface: .clients, route: .demoClientDetail,
                title: AppLocalization.localized("tour.cd.addpet.title", value: "Add a New Pet"),
                directive: AppLocalization.localized("tour.cd.addpet.directive", value: "Tap the paw button to add another pet to this owner."),
                purpose: AppLocalization.localized("tour.cd.addpet.purpose", value: "When a client adopts or brings in a new dog or cat, add it here. Every pet keeps its own profile, photo, breed, health notes, behavior tags, and visit history under the same owner — no need to create a second client."),
                lesson: .clientRecords,
                coachTip: AppLocalization.localized("tour.cd.addpet.tip", value: "One owner can have any number of pets. Add them anytime as the family grows."),
                icon: "pawprint.badge.plus",
                shape: addPetSpotlightShape,
                fallback: addPetSpotlightFallback
            ),
            WalkthroughStep(
                id: next(), anchor: .cdCheckIn, surface: .clients, route: .demoClientDetail,
                title: AppLocalization.localized("tour.cd.checkin.title", value: "Check In"),
                directive: AppLocalization.localized("tour.cd.checkin.directive", value: "Start the grooming session."),
                purpose: AppLocalization.localized("tour.cd.checkin.purpose", value: "Check In creates an active visit, starts the timer, changes the pet status to in session, and makes checkout available when the groom is finished."),
                lesson: .dailyWorkflow,
                coachTip: AppLocalization.localized("tour.cd.checkin.tip", value: "Use it when the pet is physically in your care so duration and dashboard counts stay accurate."),
                icon: "play.fill",
                allowsTargetInteraction: true,
                requiresTargetAction: true
            ),
            WalkthroughStep(
                id: next(), anchor: .cdCheckOut, surface: .clients, route: .demoClientDetail,
                title: AppLocalization.localized("tour.cd.checkout.title", value: "Check Out"),
                directive: AppLocalization.localized("tour.cd.checkout.directive", value: "Finish the visit and collect payment."),
                purpose: AppLocalization.localized("tour.cd.checkout.purpose", value: "Check Out opens after a pet is checked in. That checkout process records services, notes, photos, payment method, tips, receipt details, and a final review before saving."),
                lesson: .checkoutAndMoney,
                coachTip: AppLocalization.localized("tour.cd.checkout.tip", value: "If this button is dimmed, the pet has not been checked in yet."),
                icon: "stop.fill",
                allowsTargetInteraction: true,
                requiresTargetAction: true
            ),
            WalkthroughStep(
                id: next(), anchor: .coServices, surface: .clients, route: .demoClientDetail,
                title: AppLocalization.localized("tour.co.services.title", value: "Checkout: Services"),
                directive: AppLocalization.localized("tour.co.services.directive", value: "Build the ticket from the real service menu."),
                purpose: AppLocalization.localized("tour.co.services.purpose", value: "Services is where you choose the main groom and add-ons. Those selections build the subtotal with exact Decimal money math before the visit moves to notes, payment, and review."),
                lesson: .checkoutAndMoney,
                coachTip: AppLocalization.localized("tour.co.services.tip", value: "Main services and add-ons come from Settings, so your checkout stays consistent with your shop menu."),
                icon: "list.bullet.rectangle.portrait.fill",
                presents: .checkout
            ),
            WalkthroughStep(
                id: next(), anchor: .coDetails, surface: .clients, route: .demoClientDetail,
                title: AppLocalization.localized("tour.co.details.title", value: "Checkout: Notes & Photos"),
                directive: AppLocalization.localized("tour.co.details.directive", value: "Document what happened during the groom."),
                purpose: AppLocalization.localized("tour.co.details.purpose", value: "Notes, behavior tags, and before/after photos stay attached to this visit so history tells the full story later, not just the price."),
                lesson: .checkoutAndMoney,
                coachTip: AppLocalization.localized("tour.co.details.tip", value: "Use behavior tags for safety patterns the team should remember next time."),
                icon: "note.text.badge.plus",
                presents: .checkout
            ),
            WalkthroughStep(
                id: next(), anchor: .coPayment, surface: .clients, route: .demoClientDetail,
                title: AppLocalization.localized("tour.co.payment.title", value: "Checkout: Payment"),
                directive: AppLocalization.localized("tour.co.payment.directive", value: "Confirm the amount and how the client paid."),
                purpose: AppLocalization.localized("tour.co.payment.purpose", value: "Payment captures the final amount, payment method, tip, and any required card or transfer reference so receipts and bookkeeping match the real transaction."),
                lesson: .checkoutAndMoney,
                coachTip: AppLocalization.localized("tour.co.payment.tip", value: "You can override the amount when needed; tips and totals still stay separated for reporting."),
                icon: "creditcard.fill",
                presents: .checkout
            ),
            WalkthroughStep(
                id: next(), anchor: .coReview, surface: .clients, route: .demoClientDetail,
                title: AppLocalization.localized("tour.co.review.title", value: "Checkout: Review"),
                directive: AppLocalization.localized("tour.co.review.directive", value: "Check the record before saving it."),
                purpose: AppLocalization.localized("tour.co.review.purpose", value: "Review shows the pet, duration, services, notes, photos, payment details, and what will save to history before anything updates insights."),
                lesson: .checkoutAndMoney,
                coachTip: AppLocalization.localized("tour.co.review.tip", value: "This is the final pause to catch a missing add-on, note, or payment reference."),
                icon: "checklist.checked",
                presents: .checkout
            ),
            WalkthroughStep(
                id: next(), anchor: .coConfirm, surface: .clients, route: .demoClientDetail,
                title: AppLocalization.localized("tour.co.confirm.title", value: "Confirm & Save"),
                directive: AppLocalization.localized("tour.co.confirm.directive", value: "This is the real checkout finish line."),
                purpose: AppLocalization.localized("tour.co.confirm.purpose", value: "Confirm & Pay completes the visit, saves the payment, updates the client and pet history, refreshes insights, and prepares receipt details. The walkthrough moves on without charging or saving a demo checkout."),
                lesson: .checkoutAndMoney,
                coachTip: AppLocalization.localized("tour.co.confirm.tip", value: "During real use, only press this once the client has paid and the visit details are right."),
                icon: "checkmark.seal.fill",
                presents: .checkout
            ),
            WalkthroughStep(
                id: next(), anchor: .cdPetHistory, surface: .clients, route: .demoClientDetail,
                title: AppLocalization.localized("tour.cd.pet_history.title", value: "Pet History"),
                directive: AppLocalization.localized("tour.cd.pet_history.directive", value: "Open the pet’s full timeline."),
                purpose: AppLocalization.localized("tour.cd.pet_history.purpose", value: "History shows past visits for this pet with services, notes, payment details, photos, search, date filters, and export tools when you need records outside the app."),
                lesson: .checkoutAndMoney,
                icon: "clock.arrow.circlepath"
            ),
            WalkthroughStep(
                id: next(), anchor: .cdHistory, surface: .clients, route: .demoClientDetail,
                title: AppLocalization.localized("tour.cd.history.title", value: "Recent History"),
                directive: AppLocalization.localized("tour.cd.history.directive", value: "Review what happened last time."),
                purpose: AppLocalization.localized("tour.cd.history.purpose", value: "Completed checkouts roll into this client timeline automatically. Use All or Last 90d to answer pricing questions, repeat services, verify notes, and open a saved visit record."),
                lesson: .checkoutAndMoney,
                icon: "clock.arrow.circlepath"
            ),
            // MARK: Insights
            WalkthroughStep(
                id: next(), anchor: .insights, surface: .insights,
                title: AppLocalization.localized("tour.nav.insights.title", value: "Insights"),
                directive: AppLocalization.localized("tour.nav.insights.directive", value: "Let the app do the math."),
                purpose: AppLocalization.localized("tour.nav.insights.purpose", value: "Revenue, top services, payment mix, categories, retention, and visit trends are calculated automatically from completed checkouts."),
                lesson: .businessInsights,
                coachTip: AppLocalization.localized("tour.nav.insights.tip", value: "Use Insights after a busy day to spot pricing, staffing, and rebooking opportunities."),
                icon: "chart.bar.fill", fallback: .tabBarItem(index: 2, count: 4)
            ),
            WalkthroughStep(
                id: next(), anchor: .insKpis, surface: .insights,
                title: AppLocalization.localized("tour.ins.kpis.title", value: "Headline numbers"),
                directive: AppLocalization.localized("tour.ins.kpis.directive", value: "The three that matter most."),
                purpose: AppLocalization.localized("tour.ins.kpis.purpose", value: "Total revenue, average visit value, and returning-client retention give you business health in one row."),
                lesson: .businessInsights,
                icon: "number"
            ),
            WalkthroughStep(
                id: next(), anchor: .insRevenue, surface: .insights,
                title: AppLocalization.localized("tour.ins.revenue.title", value: "Revenue over time"),
                directive: AppLocalization.localized("tour.ins.revenue.directive", value: "Spot your trend."),
                purpose: AppLocalization.localized("tour.ins.revenue.purpose", value: "Switch between 7, 30, and 90 days to tell a good stretch from a slow one and see where the business is heading."),
                lesson: .businessInsights,
                icon: "dollarsign.circle.fill"
            ),
            WalkthroughStep(
                id: next(), anchor: .insMonthly, surface: .insights,
                title: AppLocalization.localized("tour.ins.monthly.title", value: "Monthly Performance"),
                directive: AppLocalization.localized("tour.ins.monthly.directive", value: "Compare month by month."),
                purpose: AppLocalization.localized("tour.ins.monthly.purpose", value: "Find busy seasons, slow windows, and promotion timing without building your own spreadsheet."),
                lesson: .businessInsights,
                icon: "calendar"
            ),
            WalkthroughStep(
                id: next(), anchor: .insServices, surface: .insights,
                title: AppLocalization.localized("tour.ins.services.title", value: "Service Profitability"),
                directive: AppLocalization.localized("tour.ins.services.directive", value: "Learn what earns the most."),
                purpose: AppLocalization.localized("tour.ins.services.purpose", value: "See which services drive revenue, average ticket size, and repeat demand so you can promote the winners and rethink the rest."),
                lesson: .businessInsights,
                coachTip: AppLocalization.localized("tour.ins.services.tip", value: "Keep your service menu tidy in Settings so these charts stay meaningful."),
                icon: "scissors"
            ),
            WalkthroughStep(
                id: next(), anchor: .insPaymentMix, surface: .insights,
                title: AppLocalization.localized("tour.ins.payment.title", value: "Payment Mix"),
                directive: AppLocalization.localized("tour.ins.payment.directive", value: "Know how clients pay."),
                purpose: AppLocalization.localized("tour.ins.payment.purpose", value: "Cash, card, debit, Zelle, or transfer: knowing your mix helps you plan deposits and spot processing-fee patterns."),
                lesson: .checkoutAndMoney,
                icon: "creditcard.fill"
            ),
            WalkthroughStep(
                id: next(), anchor: .insCategory, surface: .insights,
                title: AppLocalization.localized("tour.ins.category.title", value: "Visits by Category"),
                directive: AppLocalization.localized("tour.ins.category.directive", value: "See where your time goes."),
                purpose: AppLocalization.localized("tour.ins.category.purpose", value: "A breakdown of grooms, add-ons, packages, and special care shows what your shop actually does most."),
                lesson: .businessInsights,
                icon: "square.grid.2x2"
            ),
            // MARK: Settings
            WalkthroughStep(
                id: next(), anchor: .settings, surface: .settings,
                title: AppLocalization.localized("tour.nav.settings.title", value: "Settings & Start Fresh"),
                directive: AppLocalization.localized("tour.nav.settings.directive", value: "Make Pawtrackr match your shop."),
                purpose: AppLocalization.localized("tour.nav.settings.purpose", value: "Tune business details, preferences, security, exports, service setup, iCloud sync, help tools, and the Start Fresh reset from Settings."),
                lesson: .settingsAndSafety,
                coachTip: AppLocalization.localized("tour.nav.settings.tip", value: "Settings is also where you replay this walkthrough after training someone new."),
                icon: "gearshape.fill", fallback: .tabBarItem(index: 3, count: 4)
            ),
            WalkthroughStep(
                id: next(), anchor: .setBusiness, surface: .settings,
                title: AppLocalization.localized("tour.set.business.title", value: "Business profile"),
                directive: AppLocalization.localized("tour.set.business.directive", value: "Brand the workspace."),
                purpose: AppLocalization.localized("tour.set.business.purpose", value: "Set your business name, currency, logo, brand color, language, theme, haptics, and default opening tab so receipts and reports feel like yours."),
                lesson: .settingsAndSafety,
                icon: "building.2.fill"
            ),
            WalkthroughStep(
                id: next(), anchor: .setSecurity, surface: .settings,
                title: AppLocalization.localized("tour.set.security.title", value: "Security"),
                directive: AppLocalization.localized("tour.set.security.directive", value: "Protect client data."),
                purpose: AppLocalization.localized("tour.set.security.purpose", value: "Turn on App Lock, choose or change a PIN, add Face ID or Touch ID, and auto-lock when the app closes or sits idle."),
                lesson: .settingsAndSafety,
                coachTip: AppLocalization.localized("tour.set.security.tip", value: "Solo users can skip the PIN during setup and enable it later here."),
                icon: "lock.shield.fill"
            ),
            WalkthroughStep(
                id: next(), anchor: .setData, surface: .settings,
                title: AppLocalization.localized("tour.set.data.title", value: "Export your data"),
                directive: AppLocalization.localized("tour.set.data.directive", value: "Your records are yours."),
                purpose: AppLocalization.localized("tour.set.data.purpose", value: "Export clients and visits to CSV anytime for bookkeeping, backups, support, or moving data between workflows."),
                lesson: .dataOwnership,
                icon: "square.and.arrow.up"
            ),
            WalkthroughStep(
                id: next(), anchor: .setICloud, surface: .settings,
                title: AppLocalization.localized("tour.set.icloud.title", value: "iCloud sync"),
                directive: AppLocalization.localized("tour.set.icloud.directive", value: "Same shop, every device."),
                purpose: AppLocalization.localized("tour.set.icloud.purpose", value: "With iCloud enabled, clients, pets, visits, photos, settings, and checkout history sync across iPhone, iPad, and Mac with diagnostics when something needs attention."),
                lesson: .dataOwnership,
                coachTip: AppLocalization.localized("tour.set.icloud.tip", value: "The top account banner tells you if iCloud needs sign-in or network attention."),
                icon: "icloud.fill"
            ),
            WalkthroughStep(
                id: next(), anchor: .setAbout, surface: .settings,
                title: AppLocalization.localized("tour.set.about.title", value: "Replay & Start Fresh"),
                directive: AppLocalization.localized("tour.set.about.directive", value: "Replay this walkthrough whenever someone needs training."),
                purpose: AppLocalization.localized("tour.set.about.purpose", value: "The replay button brings this guided tour back without changing clients, pets, visits, settings, or reports."),
                lesson: .dataOwnership,
                icon: "sparkles"
            ),
            WalkthroughStep(
                id: next(), anchor: .setStartFresh, surface: .settings,
                title: AppLocalization.localized("tour.set.start_fresh.title", value: "Wipe & Start Fresh"),
                directive: AppLocalization.localized("tour.set.start_fresh.directive", value: "Use this when you are done practicing."),
                purpose: AppLocalization.localized("tour.set.start_fresh.purpose", value: "After you know your way around, Wipe & Start Fresh clears the demo clients, pets, visits, payments, and history so you can begin with an empty workspace for real business."),
                lesson: .dataOwnership,
                coachTip: AppLocalization.localized("tour.set.start_fresh.tip", value: "Your business profile and service menu stay in place; only operational records are removed."),
                icon: "trash.fill"
            )
        ]
    }
}
