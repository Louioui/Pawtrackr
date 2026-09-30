//
//  WalkthroughController.swift
//  Pawtrackr
//
//  Drives the interactive, step-by-step product tour. The tour is a catalog
//  of stops grouped into seven lessons. A role decides the lesson order and
//  some coach tips, what the store and device hold (`WalkthroughTourContext`)
//  decides which stops apply and how they read, and saved progress
//  (`WalkthroughProgress`) lets the tour continue where it stopped or replay
//  a single lesson.
//

import SwiftUI
import SwiftData
import OSLog

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
    case setupChecklist
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
    case cdLoyalty
    case cdPets
    case petGenderDots
    case emergencyContactBadges
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
    case setLoyalty
    case setSecurity
    case setData
    case setICloud
    case setDevices
    case setAbout
    case setStartFresh
    // Client list
    case clientFilters
    case clientSort
    case loyaltySimulator
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

/// The real action a hands-on stop waits for. The screen that sees the action
/// reports it with `WalkthroughController.observe(_:)`, and the tour moves on.
enum WalkthroughTrigger: String, Equatable, Sendable {
    /// The client list's Sort by choice changed.
    case clientSortChanged
    /// The emergency contact form was opened from the card and closed again.
    case emergencyContactEditorClosed
    /// A pet was added to the client on screen.
    case petAdded
}

/// The tour's lessons. Every stop belongs to exactly one, a lesson's stops are
/// contiguous in every tour, and a role decides the order (`tourLessonOrder`).
/// Raw values are stored in UserDefaults as completed lessons, so never
/// rename them.
enum WalkthroughLesson: String, CaseIterable, Hashable, Codable, Sendable {
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

extension OnboardingRole {
    /// The lessons this role's tour teaches, in order. The front desk starts
    /// with the work at the counter. The owner starts with the map, the
    /// numbers, setup and data safety. Lessons with no stops for the role
    /// (Insights and Settings for the front desk) are left out.
    var tourLessonOrder: [WalkthroughLesson] {
        switch self {
        case .ownerManager:
            return [.appMap, .businessInsights, .settingsAndSafety, .dataOwnership, .dailyWorkflow, .clientRecords, .checkoutAndMoney]
        case .frontDeskGroomer:
            return [.dailyWorkflow, .clientRecords, .checkoutAndMoney, .appMap, .dataOwnership]
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
    /// Stable identifier, e.g. "cd.checkin". Saved progress refers to it, so
    /// it must survive reordering and copy changes. Never reuse or rename one.
    let id: String
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
    var purpose: String
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
    /// The overlay still shows Next when the target never appears or the host
    /// says the action can't happen (`releaseActionRequirement`).
    var requiresTargetAction = false
    /// Left out of the front desk tour.
    var isOwnerOnly = false
    /// Roles whose tour leaves this stop out. The owner's tour is the
    /// shorter curriculum: it skips the counter-side dashboard lists, the
    /// checkout notes stop, and the secondary Insights charts.
    var excludedRoles: Set<OnboardingRole> = []
    /// Skipped, instead of shown as a centered bubble, when its target isn't
    /// on screen. For sections that only exist with data, like Needs Attention.
    var skipsWhenTargetMissing = false
    /// The real action that moves a hands-on stop on. Next stays available.
    var advancesOn: WalkthroughTrigger? = nil
}

extension WalkthroughStep {
    /// Stops that point at one pet on the tour client, or at its visit.
    var needsTourPet: Bool {
        presents == .checkout || [.cdPets, .petGenderDots, .cdCheckIn, .cdCheckOut, .cdPetHistory].contains(anchor)
    }

    /// The same stop with the highlighted control made look-only: the bubble
    /// shows Next, and a tap on the control advances the tour instead of
    /// checking a pet in, opening checkout or saving a form.
    func explainingOnly() -> WalkthroughStep {
        var step = self
        step.requiresTargetAction = false
        step.allowsTargetInteraction = false
        step.advancesOn = nil
        switch id {
        case WalkthroughStepID.newClientSave:
            // The hands-on copy invites a tap on Create, which is locked here.
            step.purpose = AppLocalization.localized(
                "tour.nc.save.purpose_explain",
                value: "Create saves the client for check in, services, checkout, receipts, and history. In this replay the form is look-only, so use Next to continue."
            )
        case WalkthroughStepID.clientSort:
            step.purpose = AppLocalization.localized(
                "tour.clients.sort.purpose_explain",
                value: "Last Name is the default and lists last names first. Sort by also offers First Name, Pet’s Name, Last Visit, and Newest."
            )
        case WalkthroughStepID.emergencyAdd:
            step.purpose = AppLocalization.localized(
                "tour.cd.emergency_badges.purpose_explain",
                value: "Save a name, relation, and phone. If the owner can’t be reached, staff call this person instead of searching through notes."
            )
        default:
            break
        }
        return step
    }
}

/// Stable step identifiers used outside the catalog.
enum WalkthroughStepID {
    static let dashboard = "nav.dashboard"
    static let newClientSave = "nc.save"
    static let clientSort = "clients.sort"
    static let emergencyAdd = "cd.emergency_badges"
    static let checkIn = "cd.checkin"
    static let checkOut = "cd.checkout"
    static let iCloud = "set.icloud"
    static let security = "set.security"
    static let business = "set.business"
    static let setupChecklist = "dash.checklist"
    static let loyalty = "set.loyalty"
    static let loyaltyLadder = "set.loyalty_ladder"
    static let devices = "set.devices"
    static let clientLoyalty = "cd.loyalty"
}

/// What the store and this device hold when a tour starts. It decides which
/// stops apply and how some of them read. Sample and real clients are told
/// apart by the fixed sample UUIDs, never by names.
struct WalkthroughTourContext: Equatable, Sendable {
    /// A sample client (fixed UUID) exists, so the client-detail and
    /// checkout steps have something safe to open.
    var hasSampleClient: Bool
    /// Clients that aren't sample rows exist.
    var hasRealClients: Bool
    /// The sample client the tour opens has at least one pet.
    var sampleClientHasPet: Bool = true
    /// That client's pet is checked in, so checkout has a visit to open.
    var hasActiveSampleVisit: Bool = true
    /// A real PIN is set on this device.
    var isPINSet: Bool = false
    /// The business has a name and a phone or email.
    var isBusinessProfileFilled: Bool = false
    /// This device's iCloud backup, as the rest of the app reports it.
    var backupStatus: BackupStatus = .unknown

    /// A salon holding only the sample clients, with Milo checked in: the
    /// full hands-on tour.
    static let practice = WalkthroughTourContext(hasSampleClient: true, hasRealClients: false)

    /// With real clients around, the tour only explains. It never checks a
    /// pet in, saves a client, or saves a checkout.
    var isExplainOnly: Bool { hasRealClients }

    /// Reads the store. PIN and backup status come from the caller
    /// (`AppSettings.isPINSet`, `CloudKitMonitor.backupStatus`).
    @MainActor
    static func resolve(
        in context: ModelContext,
        isPINSet: Bool = false,
        backupStatus: BackupStatus = .unknown
    ) -> WalkthroughTourContext {
        do {
            let tourClient = SampleData.tourClient(in: context)
            let tourPets = tourClient?.pets ?? []
            return WalkthroughTourContext(
                hasSampleClient: try SampleData.sampleClientCount(in: context) > 0,
                hasRealClients: try SampleData.realClientCount(in: context) > 0,
                sampleClientHasPet: !tourPets.isEmpty,
                hasActiveSampleVisit: tourPets.contains { pet in (pet.visits ?? []).contains { $0.endedAt == nil } },
                isPINSet: isPINSet,
                isBusinessProfileFilled: try businessProfileIsFilled(in: context),
                backupStatus: backupStatus
            )
        } catch {
            // Unknown store contents: explain only, and open no client.
            return WalkthroughTourContext(
                hasSampleClient: false,
                hasRealClients: true,
                isPINSet: isPINSet,
                backupStatus: backupStatus
            )
        }
    }

    private static func businessProfileIsFilled(in context: ModelContext) throws -> Bool {
        let configs = try context.fetch(FetchDescriptor<BusinessConfig>())
        return configs.contains { config in
            let hasName = !config.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasContact = [config.phone, config.email].contains { value in
                !(value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            return hasName && hasContact
        }
    }
}

// MARK: - Launch requests

/// What Settings asks the app shell to start, sent with
/// `.replayGettingStartedRequested`.
enum WalkthroughLaunchRequest: Equatable, Sendable {
    /// Replay Getting Started: saved progress cleared, the dashboard
    /// checklist re-armed, and the tour from lesson 1.
    case replayGettingStarted
    /// The tour from lesson 1 with saved progress cleared, e.g. after the
    /// role changed. The checklist is left alone.
    case startOver
    /// The whole tour from where it stopped.
    case continueTour
    /// One lesson on its own.
    case lesson(WalkthroughLesson)

    static let userInfoKey = "walkthroughLaunchRequest"

    var userInfoValue: String {
        switch self {
        case .replayGettingStarted: return "replayGettingStarted"
        case .startOver: return "startOver"
        case .continueTour: return "continue"
        case .lesson(let lesson): return "lesson:\(lesson.rawValue)"
        }
    }

    init?(userInfoValue: String) {
        switch userInfoValue {
        case "replayGettingStarted": self = .replayGettingStarted
        case "startOver": self = .startOver
        case "continue": self = .continueTour
        default:
            guard userInfoValue.hasPrefix("lesson:"),
                  let lesson = WalkthroughLesson(rawValue: String(userInfoValue.dropFirst("lesson:".count)))
            else { return nil }
            self = .lesson(lesson)
        }
    }

    /// A notification without a request, or with one this build doesn't
    /// know, replays Getting Started, as the old single Replay button did.
    init(notification: Notification) {
        let raw = notification.userInfo?[Self.userInfoKey] as? String
        self = raw.flatMap(WalkthroughLaunchRequest.init(userInfoValue:)) ?? .replayGettingStarted
    }

    func post() {
        NotificationCenter.default.post(
            name: .replayGettingStartedRequested,
            object: nil,
            userInfo: [Self.userInfoKey: userInfoValue]
        )
    }
}

// MARK: - Progress

/// One stop the user moved past with Next or the real action.
struct WalkthroughProgressEvent: Equatable, Sendable {
    let stepID: String
    let lesson: WalkthroughLesson
    /// This was the lesson's last stop in the run.
    let completesLesson: Bool
}

/// How far this device got through the tour. Saved by `AppSettings` in
/// UserDefaults, per device. Lessons are finished once their last stop is
/// passed. The last finished stop lets Continue pick up mid-lesson.
struct WalkthroughProgress: Equatable, Sendable {
    var completedLessons: Set<WalkthroughLesson> = []
    var lastCompletedStepID: String? = nil

    func recording(_ event: WalkthroughProgressEvent) -> WalkthroughProgress {
        var next = self
        next.lastCompletedStepID = event.stepID
        if event.completesLesson {
            next.completedLessons.insert(event.lesson)
        }
        return next
    }

    func isComplete(_ lesson: WalkthroughLesson) -> Bool {
        completedLessons.contains(lesson)
    }

    /// The first lesson in `order` that isn't finished.
    func nextLesson(in order: [WalkthroughLesson]) -> WalkthroughLesson? {
        order.first { !isComplete($0) }
    }

    /// "Lesson n of N" for Continue, or nil once every lesson is finished.
    func continuePosition(in order: [WalkthroughLesson]) -> (lesson: Int, of: Int)? {
        guard let next = nextLesson(in: order), let index = order.firstIndex(of: next) else { return nil }
        return (index + 1, order.count)
    }

    /// Where Continue starts in a composed tour: right after the last finished
    /// stop when that is inside the next unfinished lesson, otherwise at that
    /// lesson's first stop. Nil when every lesson in `steps` is finished.
    func resumeStepID(in steps: [WalkthroughStep]) -> String? {
        var order: [WalkthroughLesson] = []
        for step in steps where !order.contains(step.lesson) {
            order.append(step.lesson)
        }
        guard let target = nextLesson(in: order) else { return nil }
        if let last = lastCompletedStepID,
           let index = steps.firstIndex(where: { $0.id == last }),
           steps.indices.contains(index + 1),
           steps[index].lesson == target,
           steps[index + 1].lesson == target {
            return steps[index + 1].id
        }
        return steps.first { $0.lesson == target }?.id
    }
}

// MARK: - Controller

/// Owns tour state. Intentionally UI-framework-light so it can be created once and
/// handed to the overlay. Driven exclusively by SwiftUI on the main thread; the
/// host gates *whether* to start (e.g. only when the app tour hasn't been seen)
/// and persists "seen" via `onFinish` and progress via `onProgress`.
@Observable
@MainActor
final class WalkthroughController {
    private(set) var steps: [WalkthroughStep] = []
    private(set) var currentIndex: Int = 0
    private(set) var isActive: Bool = false
    /// True for ~a couple of seconds after the user FINISHES the tour (not when
    /// they skip), so the host can fire a celebratory confetti burst. The host
    /// clears it via `endCelebration()` once the animation has played.
    private(set) var isCelebrating: Bool = false
    private(set) var preferredClientDetailID: PersistentIdentifier?

    /// The last move went backwards. A stop skipped for a missing target keeps
    /// going the same way, and an already-done action doesn't bounce the user
    /// forward again.
    private(set) var lastMoveWasBackward = false
    /// Some overlay drew a bubble for this step.
    private(set) var shownStepID: String?
    /// Some overlay found a target (live anchor or fallback) for this step.
    private(set) var resolvedStepID: String?
    /// Nothing drew this step in time, so the root overlay draws it.
    private(set) var orphanedStepID: String?
    /// A hands-on step that shows Next after all: its target never appeared,
    /// or the host found the action can't happen.
    private(set) var releasedActionStepID: String?

    /// How long a step may go without a drawn bubble or a target before the
    /// fallbacks kick in. `nil` turns the timer off (tests call `checkTargets()`).
    @ObservationIgnored var targetWatchdogDelay: Duration? = .seconds(2)
    @ObservationIgnored private var watchdogTask: Task<Void, Never>?

    /// Invoked exactly once when the tour ends — whether the user finished or
    /// skipped. The host persists the "tour seen" flag here so it never auto-shows
    /// again.
    var onFinish: (() -> Void)?
    /// Invoked for each stop the user moves past going forward.
    @ObservationIgnored var onProgress: ((WalkthroughProgressEvent) -> Void)?

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "Walkthrough")

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

    /// Whether the bubble offers Next. Hands-on steps hide it until the real
    /// action happens, unless the step was released.
    var currentStepShowsNext: Bool {
        guard let step = currentStep else { return false }
        return !step.requiresTargetAction || releasedActionStepID == step.id
    }

    var isCurrentStepOrphaned: Bool {
        guard let step = currentStep else { return false }
        return orphanedStepID == step.id
    }

    /// Begins the tour with the given ordered steps, at `stepID` when it is
    /// one of them. No-op if already running or the list is empty.
    func start(_ steps: [WalkthroughStep], at stepID: String? = nil) {
        guard !isActive, !steps.isEmpty else { return }
        begin(steps, at: stepID)
    }

    /// Starts the tour even if a previous run is active. Used by Settings so a
    /// replay or Continue is an explicit command instead of depending only on
    /// a UserDefaults edge.
    func restart(_ steps: [WalkthroughStep], at stepID: String? = nil) {
        guard !steps.isEmpty else { return }
        begin(steps, at: stepID)
    }

    private func begin(_ steps: [WalkthroughStep], at stepID: String?) {
        self.steps = steps
        currentIndex = stepID.flatMap { id in steps.firstIndex { $0.id == id } } ?? 0
        preferredClientDetailID = nil
        #if os(iOS)
        HapticManager.impact(.medium)
        #endif
        withAnimation(.easeInOut(duration: 0.3)) { isActive = true }
        stepDidChange(backward: false)
    }

    func focusClientDetail(_ clientID: PersistentIdentifier) {
        preferredClientDetailID = clientID
    }

    /// Advances to the next step, or finishes after the last one.
    func advance() {
        guard isActive, steps.indices.contains(currentIndex) else { return }
        #if os(iOS)
        HapticManager.impact(.light)
        #endif
        reportCompleted(currentIndex)
        if isLastStep {
            finish(completed: true)
        } else {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                currentIndex += 1
            }
            stepDidChange(backward: false)
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
        stepDidChange(backward: true)
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
            for index in currentIndex..<steps.count { reportCompleted(index) }
            finish(completed: true)
            return
        }

        for index in currentIndex..<nextIndex { reportCompleted(index) }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
            currentIndex = nextIndex
        }
        stepDidChange(backward: false)
    }

    /// A screen saw the real action a hands-on stop waits for. Returns true
    /// when that moved the tour on. Look-only stops ignore it.
    @discardableResult
    func observe(_ trigger: WalkthroughTrigger) -> Bool {
        guard let step = currentStep, step.advancesOn == trigger, step.allowsTargetInteraction else { return false }
        Self.log.info("Walkthrough step \(step.id, privacy: .public) completed by \(trigger.rawValue, privacy: .public).")
        advance()
        return true
    }

    /// Replaces one stop's coach tip in the running tour, e.g. the iCloud
    /// stop's backup line, which is read again when the stop comes up so it
    /// never reports a status that has since changed. Writes only when the
    /// text differs.
    func updateCoachTip(_ tip: String?, forStepID stepID: String) {
        guard let index = steps.firstIndex(where: { $0.id == stepID }), steps[index].coachTip != tip else { return }
        steps[index].coachTip = tip
    }

    /// Shows Next on the current hands-on step because the action can't
    /// happen (or already happened) here.
    func releaseActionRequirement(reason: String) {
        guard let step = currentStep, step.requiresTargetAction, releasedActionStepID != step.id else { return }
        Self.log.notice("Walkthrough step \(step.id, privacy: .public) shows Next: \(reason, privacy: .public).")
        releasedActionStepID = step.id
    }

    /// An overlay drew a bubble for `stepID`. `hasTarget` says whether it
    /// found something to spotlight. `adopted` is true for the root overlay
    /// drawing a step no other overlay drew.
    func noteStepShown(_ stepID: String, hasTarget: Bool, adopted: Bool = false) {
        guard currentStep?.id == stepID else { return }
        if shownStepID != stepID { shownStepID = stepID }
        if hasTarget, resolvedStepID != stepID { resolvedStepID = stepID }
        // The step's own overlay turned up late: stop the root from drawing
        // it too, which would dim the screen twice.
        if !adopted, orphanedStepID == stepID { orphanedStepID = nil }
    }

    /// Runs when a step has had its time to appear. A step nobody drew is
    /// handed to the root overlay. A hands-on step with no target shows
    /// Next. A step that only makes sense on screen is skipped.
    func checkTargets() {
        guard isActive, let step = currentStep else { return }
        if resolvedStepID != step.id {
            if step.skipsWhenTargetMissing {
                Self.log.info("Walkthrough step \(step.id, privacy: .public) skipped: its section isn't on screen.")
                skipUnavailableStep()
                return
            }
            Self.log.notice("Walkthrough step \(step.id, privacy: .public) found no target for \(step.anchor.rawValue, privacy: .public).")
            if step.requiresTargetAction, releasedActionStepID != step.id {
                releasedActionStepID = step.id
            }
        }
        if shownStepID != step.id, orphanedStepID != step.id {
            Self.log.notice("Walkthrough step \(step.id, privacy: .public) wasn't drawn by its screen; the root overlay shows it.")
            orphanedStepID = step.id
        }
    }

    /// Ends the tour early.
    func skip() { finish(completed: false) }

    /// Clears the post-completion celebration once its confetti has played.
    func endCelebration() {
        withAnimation(.easeOut(duration: 0.4)) { isCelebrating = false }
    }

    private func skipUnavailableStep() {
        if lastMoveWasBackward, currentIndex > 0 {
            goBack()
        } else {
            advance()
        }
    }

    private func reportCompleted(_ index: Int) {
        guard steps.indices.contains(index) else { return }
        let step = steps[index]
        let completesLesson = index == steps.count - 1 || steps[index + 1].lesson != step.lesson
        onProgress?(WalkthroughProgressEvent(stepID: step.id, lesson: step.lesson, completesLesson: completesLesson))
    }

    private func stepDidChange(backward: Bool) {
        if lastMoveWasBackward != backward { lastMoveWasBackward = backward }
        if shownStepID != nil { shownStepID = nil }
        if resolvedStepID != nil { resolvedStepID = nil }
        if orphanedStepID != nil { orphanedStepID = nil }
        if releasedActionStepID != nil { releasedActionStepID = nil }
        scheduleWatchdog()
    }

    private func scheduleWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = nil
        // Sections that may not exist (Needs Attention, Recent Clients) get
        // the same time as everything else: a dashboard that is still
        // loading after a tab switch must not lose a stop it would show.
        guard let delay = targetWatchdogDelay, let step = currentStep else { return }
        let stepID = step.id
        watchdogTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, self.currentStep?.id == stepID else { return }
            self.checkTargets()
        }
    }

    private func finish(completed: Bool) {
        #if os(iOS)
        HapticManager.notify(completed ? .success : .warning)
        #endif
        watchdogTask?.cancel()
        watchdogTask = nil
        withAnimation(.easeOut(duration: 0.25)) { isActive = false }
        // Reward finishing the whole tour with a confetti moment; skipping stays quiet.
        if completed {
            withAnimation(.easeIn(duration: 0.2)) { isCelebrating = true }
        }
        let handler = onFinish
        onFinish = nil
        steps = []
        currentIndex = 0
        preferredClientDetailID = nil
        shownStepID = nil
        resolvedStepID = nil
        orphanedStepID = nil
        releasedActionStepID = nil
        handler?()
    }
}

// MARK: - Tours

extension WalkthroughController {
    /// The add-pet control differs by platform, but the walkthrough only trusts
    /// a live anchor on the visible paw control. A fake toolbar fallback can point
    /// at empty macOS chrome while the real Add Pet button is in the pet section.
    static var addPetSpotlightShape: SpotlightShape {
        #if os(iOS)
        .circle
        #else
        .roundedRect(cornerRadius: 10)
        #endif
    }

    static var addPetSpotlightFallback: SpotlightFallback {
        .none
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

    /// The whole tour for a role: its lessons in the role's order, each made
    /// safe for what the store holds (`context`). The tour runs on the real,
    /// iCloud-synced store, so:
    /// - Client-detail and checkout steps only exist when a sample client is
    ///   there to open (`SampleData.tourClient`). The tour never opens a real
    ///   client.
    /// - With real clients in the store, every hands-on step only explains:
    ///   no step waits for a real tap, taps on the highlighted control move
    ///   the tour on instead of acting, and the New Client form can't save.
    static func tour(for role: OnboardingRole, context: WalkthroughTourContext) -> [WalkthroughStep] {
        let available = shaped(catalog(role: role, context: context), role: role, context: context)
        return role.tourLessonOrder.flatMap { lesson in available.filter { $0.lesson == lesson } }
    }

    /// One lesson on its own, as Settings replays it.
    static func steps(for lesson: WalkthroughLesson, role: OnboardingRole, context: WalkthroughTourContext) -> [WalkthroughStep] {
        shaped(catalog(role: role, context: context), role: role, context: context).filter { $0.lesson == lesson }
    }

    /// The role's lessons that have at least one stop in this context.
    static func lessons(for role: OnboardingRole, context: WalkthroughTourContext) -> [WalkthroughLesson] {
        let available = Set(tour(for: role, context: context).map(\.lesson))
        return role.tourLessonOrder.filter { available.contains($0) }
    }

    /// Every stop with the owner's copy for a practice salon, grouped by
    /// lesson in `WalkthroughLesson.allCases` order. The source for tests
    /// and for tours.
    static func fullTour() -> [WalkthroughStep] {
        catalog(role: .ownerManager, context: .practice)
    }

    private static func shaped(_ steps: [WalkthroughStep], role: OnboardingRole, context: WalkthroughTourContext) -> [WalkthroughStep] {
        var steps = steps
        if role == .frontDeskGroomer {
            steps.removeAll(where: \.isOwnerOnly)
        }
        steps.removeAll { $0.excludedRoles.contains(role) }
        if !context.hasSampleClient {
            steps.removeAll { $0.route == .demoClientDetail || $0.presents == .checkout }
        } else if !context.sampleClientHasPet {
            steps.removeAll(where: \.needsTourPet)
        }
        if context.isExplainOnly {
            // Nothing will check a pet in, so without a visit already in
            // session there is no checkout to open and show.
            if !context.hasActiveSampleVisit {
                steps.removeAll { $0.presents == .checkout }
            }
            steps = steps.map { $0.explainingOnly() }
        }
        return steps
    }

    /// Every stop, with copy for `role` and `context`, in lesson order.
    // swiftlint:disable:next function_body_length
    private static func catalog(role: OnboardingRole, context: WalkthroughTourContext) -> [WalkthroughStep] {
        let isFrontDesk = role == .frontDeskGroomer
        return [
            // MARK: App Map
            WalkthroughStep(
                id: WalkthroughStepID.dashboard, anchor: .dashboard, surface: .dashboard,
                title: AppLocalization.localized("tour.nav.dashboard.title", value: "Your Dashboard"),
                directive: AppLocalization.localized("tour.nav.dashboard.directive", value: "Start every day here."),
                purpose: AppLocalization.localized("tour.nav.dashboard.purpose", value: "Dashboard shows active visits, today’s money, shortcuts, reminders, and recent clients in one place."),
                lesson: .appMap,
                coachTip: isFrontDesk
                    ? AppLocalization.localized("tour.nav.dashboard.tip_front_desk", value: "Come back here between pets. In Progress shows who is still in your care.")
                    : AppLocalization.localized("tour.nav.dashboard.tip", value: "The app loop is simple: find the client, check in the pet, finish checkout, then review the numbers."),
                icon: "square.grid.2x2.fill", fallback: .tabBarItem(index: 0, count: 4)
            ),
            WalkthroughStep(
                id: WalkthroughStepID.setupChecklist, anchor: .setupChecklist, surface: .dashboard,
                title: AppLocalization.localized("tour.dash.checklist.title", value: "Getting Started"),
                directive: AppLocalization.localized("tour.dash.checklist.directive", value: "Finish setting up your salon from this list."),
                purpose: AppLocalization.localized("tour.dash.checklist.purpose", value: "Each row opens the screen where you finish it. Rows tick themselves from your data, and sample clients don’t count as yours."),
                lesson: .appMap,
                coachTip: AppLocalization.localized("tour.dash.checklist.tip", value: "The backup row ticks only when iCloud confirms an upload. The list goes away once every row is done."),
                icon: "checklist",
                isOwnerOnly: true,
                // Hidden once every row is done or the owner closed it.
                skipsWhenTargetMissing: true
            ),
            WalkthroughStep(
                id: "nav.clients", anchor: .clients, surface: .clients,
                title: AppLocalization.localized("tour.nav.clients.title", value: "Clients & Pets"),
                directive: AppLocalization.localized("tour.nav.clients.directive", value: "This is your record book."),
                purpose: AppLocalization.localized("tour.nav.clients.purpose", value: "Owners, pets, breeds, photos, health notes, behavior tags, emergency contacts, and full visit history live here."),
                lesson: .appMap,
                coachTip: AppLocalization.localized("tour.nav.clients.tip", value: "One client can have many pets, so multi-pet families stay together."),
                icon: "person.3.fill", fallback: .tabBarItem(index: 1, count: 4)
            ),

            // MARK: Daily Workflow
            WalkthroughStep(
                id: "dash.kpis", anchor: .dashKpis, surface: .dashboard,
                title: AppLocalization.localized("tour.dash.kpis.title", value: "Today at a glance"),
                directive: AppLocalization.localized("tour.dash.kpis.directive", value: "Read your live day before opening any list."),
                purpose: AppLocalization.localized("tour.dash.kpis.purpose", value: "“In Progress” is pets currently being groomed, “Completed” is how many you have finished today, and “Revenue” is what you have earned so far."),
                lesson: .dailyWorkflow,
                coachTip: isFrontDesk
                    ? AppLocalization.localized("tour.dash.kpis.tip_front_desk", value: "If In Progress doesn’t match the pets in your care, finish the check-out that was missed.")
                    : AppLocalization.localized("tour.dash.kpis.tip", value: "If a number looks off, Recent History and Insights help you reconcile the visit behind it."),
                icon: "clock.fill"
            ),
            WalkthroughStep(
                id: "dash.quick", anchor: .dashQuickActions, surface: .dashboard,
                title: AppLocalization.localized("tour.dash.quick.title", value: "Quick Actions"),
                directive: AppLocalization.localized("tour.dash.quick.directive", value: "Use these when the salon gets busy."),
                purpose: AppLocalization.localized("tour.dash.quick.purpose", value: "New Client opens the intake form. Check Out lists the pets in session so you can finish a visit and take payment."),
                lesson: .dailyWorkflow,
                coachTip: AppLocalization.localized("tour.dash.quick.tip", value: "These shortcuts mirror the real front-desk workflow so you can move fast with one hand."),
                icon: "bolt.fill"
            ),
            WalkthroughStep(
                id: "dash.attention", anchor: .dashNeedsAttention, surface: .dashboard,
                title: AppLocalization.localized("tour.dash.attention.title", value: "Needs Attention"),
                directive: AppLocalization.localized("tour.dash.attention.directive", value: "See who needs a follow-up."),
                purpose: AppLocalization.localized("tour.dash.attention.purpose", value: "Pets due for their next groom surface here, so you can call, message, and rebook them before they drift away."),
                lesson: .dailyWorkflow,
                icon: "exclamationmark.circle.fill",
                excludedRoles: [.ownerManager],
                skipsWhenTargetMissing: true
            ),
            WalkthroughStep(
                id: "clients.filters", anchor: .clientFilters, surface: .clients,
                title: AppLocalization.localized("tour.clients.filters.title", value: "Client Filters"),
                directive: AppLocalization.localized("tour.clients.filters.directive", value: "Switch between All, Active, Needs Attention, and Missing Info."),
                purpose: AppLocalization.localized("tour.clients.filters.purpose", value: "Filters turn a large client book into a working queue, so the front desk can find what needs action right now."),
                lesson: .dailyWorkflow,
                coachTip: isFrontDesk
                    ? AppLocalization.localized("tour.clients.filters.tip_front_desk", value: "Start a shift on Needs Attention to see overdue pets nobody has contacted yet.")
                    : AppLocalization.localized("tour.clients.filters.tip", value: "Missing Info helps clean up incomplete phone and email records before they cause pickup problems."),
                icon: "line.3.horizontal.decrease.circle.fill"
            ),

            // MARK: Client Records
            WalkthroughStep(
                id: "dash.recent", anchor: .dashRecentClients, surface: .dashboard,
                title: AppLocalization.localized("tour.dash.recent.title", value: "Recent Clients"),
                directive: AppLocalization.localized("tour.dash.recent.directive", value: "Pick up where you left off."),
                purpose: AppLocalization.localized("tour.dash.recent.purpose", value: "Your most recent clients are here for fast rebooking. Tap one to open the full profile, pet history, and safety notes."),
                lesson: .clientRecords,
                coachTip: AppLocalization.localized("tour.dash.recent.tip", value: "Aggressive behavior tags appear in red anywhere the team needs to notice them."),
                icon: "person.2.fill",
                excludedRoles: [.ownerManager],
                skipsWhenTargetMissing: true
            ),
            WalkthroughStep(
                id: WalkthroughStepID.clientSort, anchor: .clientSort, surface: .clients,
                title: AppLocalization.localized("tour.clients.sort.title", value: "Sort & Name Order"),
                directive: AppLocalization.localized("tour.clients.sort.directive", value: "Sort by changes the order and how names read."),
                purpose: AppLocalization.localized("tour.clients.sort.purpose", value: "Last Name is the default and lists last names first. Pick First Name here and watch the names flip. The tour moves on by itself."),
                lesson: .clientRecords,
                coachTip: AppLocalization.localized("tour.clients.sort.tip", value: "Sorted by Last Name, “Jane Doe” shows as “Doe Jane” in the list. Her profile still reads “Jane Doe”."),
                icon: "arrow.up.arrow.down",
                allowsTargetInteraction: true,
                skipsWhenTargetMissing: true,
                advancesOn: .clientSortChanged
            ),
            WalkthroughStep(
                id: "nc.owner", anchor: .ncOwner, surface: .clients,
                title: AppLocalization.localized("tour.nc.owner.title", value: "Add the owner"),
                directive: AppLocalization.localized("tour.nc.owner.directive", value: "Start with the person who books and pays."),
                purpose: AppLocalization.localized("tour.nc.owner.purpose", value: "Name, phone, email, address, and emergency contacts help you confirm appointments, follow up, and keep the right contact details on receipts and exports."),
                lesson: .clientRecords,
                coachTip: AppLocalization.localized("tour.nc.owner.tip", value: "Only a name is required. Add the rest now or fill it in later."),
                icon: "person.text.rectangle",
                presents: .newClient,
                allowsTargetInteraction: true
            ),
            WalkthroughStep(
                id: "nc.pets", anchor: .ncPets, surface: .clients,
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
                id: WalkthroughStepID.newClientSave, anchor: .ncSave, surface: .clients,
                title: AppLocalization.localized("tour.nc.save.title", value: "Save the client"),
                directive: AppLocalization.localized("tour.nc.save.directive", value: "Create once, reuse every visit."),
                purpose: AppLocalization.localized("tour.nc.save.purpose", value: "Tap Create when you are adding a real client, or use Next to keep practicing. Once saved, the client is ready for check in, services, checkout, receipts, and future history."),
                lesson: .clientRecords,
                icon: "checkmark.circle.fill",
                fallback: newClientSaveSpotlightFallback,
                presents: .newClient,
                allowsTargetInteraction: true
            ),
            WalkthroughStep(
                id: "cd.owner", anchor: .cdOwner, surface: .clients, route: .demoClientDetail,
                title: AppLocalization.localized("tour.cd.owner.title", value: "Client Details"),
                directive: AppLocalization.localized("tour.cd.owner.directive", value: "This is the profile you open from the Clients list."),
                purpose: AppLocalization.localized("tour.cd.owner.purpose", value: "The top card keeps the owner’s phone, email, address, messaging, and quick edit actions together so you can confirm details during booking or pickup."),
                lesson: .clientRecords,
                coachTip: AppLocalization.localized("tour.cd.owner.tip", value: "Use this screen before every appointment when you need contact info, pet notes, or history in one place."),
                icon: "person.crop.rectangle.stack.fill"
            ),
            WalkthroughStep(
                id: "cd.emergency", anchor: .cdEmergency, surface: .clients, route: .demoClientDetail,
                title: AppLocalization.localized("tour.cd.emergency.title", value: "Emergency Contacts"),
                directive: AppLocalization.localized("tour.cd.emergency.directive", value: "Keep backup contacts close."),
                purpose: AppLocalization.localized("tour.cd.emergency.purpose", value: "Each backup person shows relation and phone. Call dials them, and the row’s menu offers Message, Copy Phone, Edit, and Delete. A “Missing:” note lists what’s left to add."),
                lesson: .clientRecords,
                icon: "phone.badge.plus"
            ),
            WalkthroughStep(
                id: WalkthroughStepID.emergencyAdd, anchor: .emergencyContactBadges, surface: .clients, route: .demoClientDetail,
                title: AppLocalization.localized("tour.cd.emergency_badges.title", value: "Add a Backup Contact"),
                directive: AppLocalization.localized("tour.cd.emergency_badges.directive", value: "The + button adds a backup person staff can call."),
                purpose: AppLocalization.localized("tour.cd.emergency_badges.purpose", value: "Save a name, relation, and phone so staff can reach someone if the owner can’t answer. Open it now to try, or use Next."),
                lesson: .clientRecords,
                icon: "person.crop.circle.badge.plus",
                shape: .circle,
                allowsTargetInteraction: true,
                advancesOn: .emergencyContactEditorClosed
            ),
            WalkthroughStep(
                id: "cd.gender_dots", anchor: .petGenderDots, surface: .clients, route: .demoClientDetail,
                title: AppLocalization.localized("tour.cd.gender_dots.title", value: "Gender Dots"),
                directive: AppLocalization.localized("tour.cd.gender_dots.directive", value: "Blue means male and pink means female."),
                purpose: AppLocalization.localized("tour.cd.gender_dots.purpose", value: "Each pet’s name sits in a colored capsule with a dot. The same colors show on client cards, this profile, and the dashboard, so multi-pet homes are quick to scan."),
                lesson: .clientRecords,
                icon: "circle.grid.cross.fill"
            ),
            WalkthroughStep(
                id: "cd.addpet", anchor: .cdAddPet, surface: .clients, route: .demoClientDetail,
                title: AppLocalization.localized("tour.cd.addpet.title", value: "Add a New Pet"),
                directive: AppLocalization.localized("tour.cd.addpet.directive", value: "Add another pet to this owner with this button."),
                purpose: AppLocalization.localized("tour.cd.addpet.purpose", value: "When an owner gets a new dog or cat, add the pet here. The pet keeps its own photo, breed, health notes, tags, and visit history."),
                lesson: .clientRecords,
                coachTip: AppLocalization.localized("tour.cd.addpet.tip", value: "One owner can have any number of pets. Add them anytime as the family grows."),
                icon: "pawprint.fill",
                shape: addPetSpotlightShape,
                fallback: addPetSpotlightFallback,
                allowsTargetInteraction: true,
                advancesOn: .petAdded
            ),

            // MARK: Checkout & Money
            WalkthroughStep(
                id: "workflow.checkout", anchor: .dashQuickActions, surface: .dashboard,
                title: AppLocalization.localized("tour.workflow.checkout.title", value: "Check-In to Checkout"),
                directive: AppLocalization.localized("tour.workflow.checkout.directive", value: "This is the main working loop."),
                purpose: AppLocalization.localized("tour.workflow.checkout.purpose", value: "Check in starts the timer, the visit collects services, notes, and photos, and checkout records payment, tip, reference, and receipt details for history and reporting."),
                lesson: .checkoutAndMoney,
                coachTip: isFrontDesk
                    ? AppLocalization.localized("tour.workflow.checkout.tip_front_desk", value: "Check in when the pet arrives and check out at pickup, so times and totals stay right.")
                    : AppLocalization.localized("tour.workflow.checkout.tip", value: "Money uses exact Decimal calculations, so service totals, tips, and payments stay dependable."),
                icon: "arrow.triangle.2.circlepath"
            ),
            WalkthroughStep(
                id: "dash.revenue", anchor: .dashRevenue, surface: .dashboard,
                title: AppLocalization.localized("tour.dash.revenue.title", value: "Revenue (7 Days)"),
                directive: AppLocalization.localized("tour.dash.revenue.directive", value: "Watch the week while you work."),
                purpose: AppLocalization.localized("tour.dash.revenue.purpose", value: "Every completed checkout flows into this chart automatically, so you can tell a strong week from a slow one without touching a spreadsheet."),
                lesson: .checkoutAndMoney,
                icon: "chart.bar.fill",
                isOwnerOnly: true
            ),
            WalkthroughStep(
                id: WalkthroughStepID.clientLoyalty, anchor: .cdLoyalty, surface: .clients, route: .demoClientDetail,
                title: AppLocalization.localized("tour.cd.loyalty.title", value: "Loyalty Balance"),
                directive: AppLocalization.localized("tour.cd.loyalty.directive", value: "Open this card to see points, rewards, and loyalty history."),
                purpose: AppLocalization.localized("tour.cd.loyalty.purpose", value: "After checkout, earned points post here automatically so staff can redeem rewards without doing math or searching old tickets."),
                lesson: .checkoutAndMoney,
                coachTip: AppLocalization.localized("tour.cd.loyalty.tip", value: "The badge shows the current balance. The detail screen shows reward progress and the points ledger."),
                icon: "giftcard.fill"
            ),
            WalkthroughStep(
                id: "cd.pets", anchor: .cdPets, surface: .clients, route: .demoClientDetail,
                title: AppLocalization.localized("tour.cd.pets.title", value: "Pet Actions"),
                directive: AppLocalization.localized("tour.cd.pets.directive", value: "This row is where the visit work starts."),
                purpose: AppLocalization.localized("tour.cd.pets.purpose", value: "Each pet has its own status and actions. The next stops break down check-in, checkout, and history so the workflow is clear before you use it with real clients."),
                lesson: .checkoutAndMoney,
                coachTip: AppLocalization.localized("tour.cd.pets.tip", value: "Each owner can have multiple pets, and every pet keeps its own status and visit history."),
                icon: "pawprint.fill"
            ),
            WalkthroughStep(
                id: WalkthroughStepID.checkIn, anchor: .cdCheckIn, surface: .clients, route: .demoClientDetail,
                title: AppLocalization.localized("tour.cd.checkin.title", value: "Check In"),
                directive: AppLocalization.localized("tour.cd.checkin.directive", value: "Start the grooming session."),
                purpose: AppLocalization.localized("tour.cd.checkin.purpose", value: "Check In creates an active visit, starts the timer, changes the pet status to in session, and makes checkout available when the groom is finished."),
                lesson: .checkoutAndMoney,
                coachTip: isFrontDesk
                    ? AppLocalization.localized("tour.cd.checkin.tip", value: "Use it when the pet is physically in your care so duration and dashboard counts stay accurate.")
                    : AppLocalization.localized("tour.cd.checkin.tip_owner", value: "Check-in times set visit length and today’s counts, so ask the team to check in on arrival."),
                icon: "play.fill",
                allowsTargetInteraction: true,
                requiresTargetAction: true
            ),
            WalkthroughStep(
                id: WalkthroughStepID.checkOut, anchor: .cdCheckOut, surface: .clients, route: .demoClientDetail,
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
                id: "co.services", anchor: .coServices, surface: .clients, route: .demoClientDetail,
                title: AppLocalization.localized("tour.co.services.title", value: "Checkout: Services"),
                directive: AppLocalization.localized("tour.co.services.directive", value: "Build the ticket from the real service menu."),
                purpose: AppLocalization.localized("tour.co.services.purpose", value: "Services is where you choose the main groom and add-ons. Those selections build the subtotal with exact Decimal money math before the visit moves to notes, payment, and review."),
                lesson: .checkoutAndMoney,
                coachTip: AppLocalization.localized("tour.co.services.tip", value: "Main services and add-ons come from Settings, so your checkout stays consistent with your shop menu."),
                icon: "list.bullet.rectangle.portrait.fill",
                presents: .checkout
            ),
            WalkthroughStep(
                id: "co.details", anchor: .coDetails, surface: .clients, route: .demoClientDetail,
                title: AppLocalization.localized("tour.co.details.title", value: "Checkout: Notes & Photos"),
                directive: AppLocalization.localized("tour.co.details.directive", value: "Document what happened during the groom."),
                purpose: AppLocalization.localized("tour.co.details.purpose", value: "Notes, behavior tags, and before/after photos stay attached to this visit so history tells the full story later, not just the price."),
                lesson: .checkoutAndMoney,
                coachTip: AppLocalization.localized("tour.co.details.tip", value: "Use behavior tags for safety patterns the team should remember next time."),
                icon: "note.text.badge.plus",
                presents: .checkout,
                excludedRoles: [.ownerManager]
            ),
            WalkthroughStep(
                id: "co.payment", anchor: .coPayment, surface: .clients, route: .demoClientDetail,
                title: AppLocalization.localized("tour.co.payment.title", value: "Checkout: Payment"),
                directive: AppLocalization.localized("tour.co.payment.directive", value: "Confirm the amount and how the client paid."),
                purpose: AppLocalization.localized("tour.co.payment.purpose", value: "Payment captures the final amount, payment method, tip, and any required card or transfer reference so receipts and bookkeeping match the real transaction."),
                lesson: .checkoutAndMoney,
                coachTip: AppLocalization.localized("tour.co.payment.tip", value: "The tip is added to the total you collect, so revenue reports include it."),
                icon: "creditcard.fill",
                presents: .checkout
            ),
            WalkthroughStep(
                id: "co.review", anchor: .coReview, surface: .clients, route: .demoClientDetail,
                title: AppLocalization.localized("tour.co.review.title", value: "Checkout: Review"),
                directive: AppLocalization.localized("tour.co.review.directive", value: "Check the record before saving it."),
                purpose: AppLocalization.localized("tour.co.review.purpose", value: "Review shows the pet, duration, services, notes, photos, payment details, and what will save to history before anything updates insights."),
                lesson: .checkoutAndMoney,
                coachTip: AppLocalization.localized("tour.co.review.tip", value: "This is the final pause to catch a missing add-on, note, or payment reference."),
                icon: "checklist.checked",
                presents: .checkout
            ),
            WalkthroughStep(
                id: "co.confirm", anchor: .coConfirm, surface: .clients, route: .demoClientDetail,
                title: AppLocalization.localized("tour.co.confirm.title", value: "Confirm & Save"),
                directive: AppLocalization.localized("tour.co.confirm.directive", value: "This is the real checkout finish line."),
                purpose: AppLocalization.localized("tour.co.confirm.purpose", value: "Confirm & Pay saves the payment, updates history, refreshes insights, and prepares receipt details. This demo tour does not charge or save."),
                lesson: .checkoutAndMoney,
                coachTip: AppLocalization.localized("tour.co.confirm.tip", value: "After payment, loyalty points post to the client profile automatically."),
                icon: "checkmark.seal.fill",
                presents: .checkout
            ),
            WalkthroughStep(
                id: "cd.pet_history", anchor: .cdPetHistory, surface: .clients, route: .demoClientDetail,
                title: AppLocalization.localized("tour.cd.pet_history.title", value: "Pet History"),
                directive: AppLocalization.localized("tour.cd.pet_history.directive", value: "Open the pet’s full timeline."),
                purpose: AppLocalization.localized("tour.cd.pet_history.purpose", value: "History shows past visits for this pet with services, notes, payment details, photos, search, date filters, and export tools when you need records outside the app."),
                lesson: .checkoutAndMoney,
                icon: "clock.arrow.circlepath"
            ),
            WalkthroughStep(
                id: "cd.history", anchor: .cdHistory, surface: .clients, route: .demoClientDetail,
                title: AppLocalization.localized("tour.cd.history.title", value: "Recent History"),
                directive: AppLocalization.localized("tour.cd.history.directive", value: "Review what happened last time."),
                purpose: AppLocalization.localized("tour.cd.history.purpose", value: "Completed checkouts roll into this client timeline automatically. Use All or Last 90d to answer pricing questions, repeat services, verify notes, and open a saved visit record."),
                lesson: .checkoutAndMoney,
                icon: "clock.arrow.circlepath"
            ),

            // MARK: Business Insights
            WalkthroughStep(
                id: "nav.insights", anchor: .insights, surface: .insights,
                title: AppLocalization.localized("tour.nav.insights.title", value: "Insights"),
                directive: AppLocalization.localized("tour.nav.insights.directive", value: "Let the app do the math."),
                purpose: AppLocalization.localized("tour.nav.insights.purpose", value: "Insights turns finished checkouts into revenue, services, payments, retention, and visit trend charts."),
                lesson: .businessInsights,
                coachTip: AppLocalization.localized("tour.nav.insights.tip", value: "Use Insights after a busy day to spot pricing, staffing, and rebooking opportunities."),
                icon: "chart.bar.fill", fallback: .tabBarItem(index: 2, count: 4),
                isOwnerOnly: true
            ),
            WalkthroughStep(
                id: "ins.kpis", anchor: .insKpis, surface: .insights,
                title: AppLocalization.localized("tour.ins.kpis.title", value: "Headline numbers"),
                directive: AppLocalization.localized("tour.ins.kpis.directive", value: "The three that matter most."),
                purpose: AppLocalization.localized("tour.ins.kpis.purpose", value: "Total revenue, average visit value, and returning-client retention give you business health in one row."),
                lesson: .businessInsights,
                icon: "number",
                isOwnerOnly: true
            ),
            WalkthroughStep(
                id: "ins.revenue", anchor: .insRevenue, surface: .insights,
                title: AppLocalization.localized("tour.ins.revenue.title", value: "Revenue over time"),
                directive: AppLocalization.localized("tour.ins.revenue.directive", value: "Spot your trend."),
                purpose: AppLocalization.localized("tour.ins.revenue.purpose", value: "Switch between 7, 30, and 90 days to tell a good stretch from a slow one and see where the business is heading."),
                lesson: .businessInsights,
                icon: "dollarsign.circle.fill",
                isOwnerOnly: true
            ),
            WalkthroughStep(
                id: "ins.monthly", anchor: .insMonthly, surface: .insights,
                title: AppLocalization.localized("tour.ins.monthly.title", value: "Monthly Performance"),
                directive: AppLocalization.localized("tour.ins.monthly.directive", value: "Compare month by month."),
                purpose: AppLocalization.localized("tour.ins.monthly.purpose", value: "Find busy seasons, slow windows, and promotion timing without building your own spreadsheet."),
                lesson: .businessInsights,
                icon: "calendar",
                // Owner-only and left out of the owner's tour, so no tour
                // shows it. Same for Payment Mix and Visits by Category.
                // `fullTour()` still has all three.
                isOwnerOnly: true,
                excludedRoles: [.ownerManager]
            ),
            WalkthroughStep(
                id: "ins.services", anchor: .insServices, surface: .insights,
                title: AppLocalization.localized("tour.ins.services.title", value: "Service Profitability"),
                directive: AppLocalization.localized("tour.ins.services.directive", value: "Learn what earns the most."),
                purpose: AppLocalization.localized("tour.ins.services.purpose", value: "See which services drive revenue, average ticket size, and repeat demand so you can promote the winners and rethink the rest."),
                lesson: .businessInsights,
                coachTip: AppLocalization.localized("tour.ins.services.tip", value: "Keep your service menu tidy in Settings so these charts stay meaningful."),
                icon: "scissors",
                isOwnerOnly: true
            ),
            WalkthroughStep(
                id: "ins.payment", anchor: .insPaymentMix, surface: .insights,
                title: AppLocalization.localized("tour.ins.payment.title", value: "Payment Mix"),
                directive: AppLocalization.localized("tour.ins.payment.directive", value: "Know how clients pay."),
                purpose: AppLocalization.localized("tour.ins.payment.purpose", value: "Cash, card, debit, Zelle, or transfer: knowing your mix helps you plan deposits and spot processing-fee patterns."),
                lesson: .businessInsights,
                icon: "creditcard.fill",
                isOwnerOnly: true,
                excludedRoles: [.ownerManager]
            ),
            WalkthroughStep(
                id: "ins.category", anchor: .insCategory, surface: .insights,
                title: AppLocalization.localized("tour.ins.category.title", value: "Visits by Category"),
                directive: AppLocalization.localized("tour.ins.category.directive", value: "See where your time goes."),
                purpose: AppLocalization.localized("tour.ins.category.purpose", value: "A breakdown of grooms, add-ons, packages, and special care shows what your shop actually does most."),
                lesson: .businessInsights,
                icon: "square.grid.2x2",
                isOwnerOnly: true,
                excludedRoles: [.ownerManager]
            ),

            // MARK: Settings & Safety
            WalkthroughStep(
                id: "nav.settings", anchor: .settings, surface: .settings,
                title: AppLocalization.localized("tour.nav.settings.title", value: "Settings & Start Fresh"),
                directive: AppLocalization.localized("tour.nav.settings.directive", value: "Make Pawtrackr match your shop."),
                purpose: AppLocalization.localized("tour.nav.settings.purpose", value: "Tune business details, preferences, security, exports, service setup, iCloud sync, help tools, and the Start Fresh reset from Settings."),
                lesson: .settingsAndSafety,
                coachTip: AppLocalization.localized("tour.nav.settings.tip", value: "Settings is also where you continue this tour or replay one lesson for someone new."),
                icon: "gearshape.fill", fallback: .tabBarItem(index: 3, count: 4),
                isOwnerOnly: true
            ),
            WalkthroughStep(
                id: WalkthroughStepID.business, anchor: .setBusiness, surface: .settings,
                title: AppLocalization.localized("tour.set.business.title", value: "Business profile"),
                directive: context.isBusinessProfileFilled
                    ? AppLocalization.localized("tour.set.business.directive_filled", value: "Your business details are in. Update them here anytime.")
                    : AppLocalization.localized("tour.set.business.directive", value: "Brand the workspace."),
                purpose: AppLocalization.localized("tour.set.business.purpose", value: "Set your business name, currency, logo, brand color, language, theme, haptics, and default opening tab so receipts and reports feel like yours."),
                lesson: .settingsAndSafety,
                coachTip: context.isBusinessProfileFilled
                    ? AppLocalization.localized("tour.set.business.tip_filled", value: "Receipts show the phone and email saved here, so keep them current.")
                    : AppLocalization.localized("tour.set.business.tip", value: "Add your phone or email so receipts show clients how to reach you."),
                icon: "building.2.fill",
                isOwnerOnly: true
            ),
            WalkthroughStep(
                id: WalkthroughStepID.loyaltyLadder, anchor: .setLoyalty, surface: .settings,
                title: AppLocalization.localized("tour.set.loyalty_ladder.title", value: "Loyalty ladder"),
                directive: AppLocalization.localized("tour.set.loyalty_ladder.directive", value: "Pick rewards before staff start checking out."),
                purpose: AppLocalization.localized("tour.set.loyalty_ladder.purpose", value: "Rewards 2.0 is $5 Off, $20 Off, 25% Off and Free Bath, and checkout takes them off the bill. Use Rewards 2.0 replaces every reward on the list, custom ones included. Client points stay as they are."),
                lesson: .settingsAndSafety,
                coachTip: AppLocalization.localized("tour.set.loyalty_ladder.tip", value: "Keep rewards easy to explain at pickup: points should feel automatic, not like extra paperwork."),
                icon: "giftcard.fill",
                isOwnerOnly: true
            ),
            WalkthroughStep(
                id: WalkthroughStepID.loyalty, anchor: .loyaltySimulator, surface: .settings,
                title: AppLocalization.localized("tour.set.loyalty.title", value: "Loyalty points"),
                directive: AppLocalization.localized("tour.set.loyalty.directive", value: "Try your loyalty rules before a client earns anything."),
                purpose: AppLocalization.localized("tour.set.loyalty.purpose", value: "Move the checkout total, pick a tier, and see the points a visit earns. Checkout awards points with this same math, and the rules sit right above."),
                lesson: .settingsAndSafety,
                coachTip: AppLocalization.localized("tour.set.loyalty.tip", value: "Apply a reward on the Payment step at checkout and it comes off the bill, or redeem it from Loyalty & Rewards on the client's profile."),
                icon: "giftcard.fill",
                isOwnerOnly: true
            ),
            WalkthroughStep(
                id: WalkthroughStepID.security, anchor: .setSecurity, surface: .settings,
                title: AppLocalization.localized("tour.set.security.title", value: "Security"),
                directive: AppLocalization.localized("tour.set.security.directive", value: "Protect client data."),
                purpose: AppLocalization.localized("tour.set.security.purpose", value: "Turn on App Lock, choose or change a PIN, add Face ID or Touch ID, and auto-lock when the app closes or sits idle."),
                lesson: .settingsAndSafety,
                coachTip: context.isPINSet
                    ? AppLocalization.localized("tour.set.security.tip_pin_set", value: "Your PIN is set on this device. Change it here anytime.")
                    : AppLocalization.localized("tour.set.security.tip", value: "Solo users can skip the PIN during setup and enable it later here."),
                icon: "lock.shield.fill",
                isOwnerOnly: true
            ),

            // MARK: Data Ownership
            WalkthroughStep(
                id: "set.data", anchor: .setData, surface: .settings,
                title: AppLocalization.localized("tour.set.data.title", value: "Export your data"),
                directive: AppLocalization.localized("tour.set.data.directive", value: "Your records are yours."),
                purpose: AppLocalization.localized("tour.set.data.purpose", value: "Export clients and visits to CSV anytime for bookkeeping, backups, support, or moving data between workflows."),
                lesson: .dataOwnership,
                icon: "square.and.arrow.up",
                isOwnerOnly: true
            ),
            WalkthroughStep(
                id: WalkthroughStepID.iCloud, anchor: .setICloud, surface: .settings,
                title: AppLocalization.localized("tour.set.icloud.title", value: "iCloud sync"),
                directive: AppLocalization.localized("tour.set.icloud.directive", value: "“Backed up” means iCloud confirmed the upload."),
                purpose: AppLocalization.localized("tour.set.icloud.purpose", value: "With iCloud on, clients, pets, visits, photos, and checkout history sync to your iPhone, iPad, and Mac, with business name, currency, and brand color. Other settings stay per device."),
                lesson: .dataOwnership,
                coachTip: iCloudTip(for: context.backupStatus),
                icon: "icloud.fill"
            ),
            WalkthroughStep(
                id: WalkthroughStepID.devices, anchor: .setDevices, surface: .settings,
                title: AppLocalization.localized("tour.set.devices.title", value: "Synced devices"),
                directive: AppLocalization.localized("tour.set.devices.directive", value: "See which phones, iPads, and Macs share your data and when each was last seen."),
                purpose: AppLocalization.localized("tour.set.devices.purpose", value: "Device health shows recently seen workstations, iCloud context, and stale devices so managers can spot sync gaps before staff rely on old records."),
                lesson: .dataOwnership,
                coachTip: AppLocalization.localized("tour.set.devices.tip", value: "If a device needs a check, use iCloud diagnostics before resetting anything."),
                icon: "iphone.gen3.radiowaves.left.and.right"
            ),
            WalkthroughStep(
                id: "set.about", anchor: .setAbout, surface: .settings,
                title: AppLocalization.localized("tour.set.about.title", value: "Replay & Start Fresh"),
                directive: AppLocalization.localized("tour.set.about.directive", value: "Continue the tour or replay one lesson for someone new."),
                purpose: AppLocalization.localized("tour.set.about.purpose", value: "Pick up where you stopped or replay a lesson. When your salon has real clients, the tour only explains. It never checks pets in, creates clients, or saves a checkout."),
                lesson: .dataOwnership,
                icon: "sparkles",
                isOwnerOnly: true
            ),
            WalkthroughStep(
                id: "set.start_fresh", anchor: .setStartFresh, surface: .settings,
                title: AppLocalization.localized("tour.set.start_fresh.title", value: "Wipe & Start Fresh"),
                directive: AppLocalization.localized("tour.set.start_fresh.directive", value: "Only for erasing the whole salon, real clients included."),
                purpose: AppLocalization.localized("tour.set.start_fresh.purpose", value: "Wipe & Start Fresh erases every client, pet, visit, payment and report, real or sample, on all your devices through iCloud. Use it to begin with an empty workspace for real business."),
                lesson: .dataOwnership,
                coachTip: AppLocalization.localized("tour.set.start_fresh.tip", value: "To drop only the sample clients, use Remove Sample Clients. Your own clients stay."),
                icon: "trash.fill",
                isOwnerOnly: true
            )
        ]
    }

    /// One line about this device's backup, true to `BackupStatus`: "Backed
    /// up as of…" only when iCloud confirmed an upload.
    static func iCloudTip(for status: BackupStatus) -> String {
        switch status {
        case .backedUp(let asOf):
            let when = asOf.formatted(
                Date.FormatStyle(date: .abbreviated, time: .shortened).locale(AppLocalization.currentLocale)
            )
            return String(
                format: AppLocalization.localized(
                    "tour.set.icloud.tip_backed_up_fmt",
                    value: "Backed up as of %@. iCloud confirmed every change this device made before then."
                ),
                when
            )
        case .uploading:
            return AppLocalization.localized(
                "tour.set.icloud.tip_uploading",
                value: "Uploading now. Changes count as backed up only after iCloud confirms them."
            )
        case .notBackedUp:
            return AppLocalization.localized(
                "tour.set.icloud.tip_not_backed_up",
                value: "Not backed up yet. Some changes on this device are still waiting for iCloud to confirm them."
            )
        case .failing:
            return AppLocalization.localized(
                "tour.set.icloud.tip_failing",
                value: "Uploads to iCloud are failing right now. This section shows what went wrong."
            )
        case .signedOut:
            return AppLocalization.localized(
                "tour.set.icloud.tip_signed_out",
                value: "No iCloud account is signed in, so nothing uploads from this device."
            )
        case .localOnly:
            return AppLocalization.localized(
                "tour.set.icloud.tip_local_only",
                value: "iCloud backup is off on this device, so nothing uploads from here."
            )
        case .unknown:
            return AppLocalization.localized(
                "tour.set.icloud.tip_checking",
                value: "Still checking the iCloud account. “Backed up” shows only after iCloud confirms an upload."
            )
        }
    }
}
