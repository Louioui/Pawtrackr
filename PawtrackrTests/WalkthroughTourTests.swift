import XCTest
import SwiftData
@testable import Pawtrackr

/// The guided tour: stable step IDs, one screen-by-screen order for every
/// role, stops chosen and worded from what the salon and device hold, saved
/// progress, hands-on stops that always have a way forward, and anchors
/// attached where the overlay that draws them can see them.
@MainActor
final class WalkthroughTourTests: XCTestCase {
    private var defaultsSuiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaultsSuiteName = "WalkthroughTourTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: AppSettingsKeys.appLanguageOverride)
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        defaults = nil
        super.tearDown()
    }

    // MARK: - Contexts

    /// Every combination the tour builder can be handed.
    private static var contextMatrix: [WalkthroughTourContext] {
        var contexts: [WalkthroughTourContext] = []
        for hasSampleClient in [true, false] {
            for hasRealClients in [false, true] {
                for (hasPet, hasVisit) in [(true, true), (true, false), (false, false)] {
                    for isPINSet in [false, true] {
                        for filled in [false, true] {
                            contexts.append(WalkthroughTourContext(
                                hasSampleClient: hasSampleClient,
                                hasRealClients: hasRealClients,
                                sampleClientHasPet: hasPet,
                                hasActiveSampleVisit: hasVisit,
                                isPINSet: isPINSet,
                                isBusinessProfileFilled: filled
                            ))
                        }
                    }
                }
            }
        }
        return contexts
    }

    private func lessonSequence(_ steps: [WalkthroughStep]) -> [WalkthroughLesson] {
        var sequence: [WalkthroughLesson] = []
        for step in steps where sequence.last != step.lesson {
            sequence.append(step.lesson)
        }
        return sequence
    }

    private func makeController() -> WalkthroughController {
        let controller = WalkthroughController()
        controller.targetWatchdogDelay = nil
        return controller
    }

    // MARK: - Stable IDs and lessons

    func testEveryStepHasAStableUniqueID() {
        let ids = WalkthroughController.fullTour().map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "Step IDs must be unique: \(ids)")
        for id in ids {
            XCTAssertFalse(id.isEmpty)
            XCTAssertEqual(id, id.lowercased(), id)
            XCTAssertFalse(id.contains(" "), id)
        }
        // Saved progress refers to these. Renaming one loses users' place.
        for id in ["dash.kpis", "nav.clients", "clients.sort", "nc.save", "cd.checkin", "cd.checkout", "co.confirm", "set.start_fresh"] {
            XCTAssertTrue(ids.contains(id), id)
        }
    }

    func testStepIDsDoNotDependOnLanguageOrContext() {
        UserDefaults.standard.set(AppLanguageOverride.es.rawValue, forKey: AppSettingsKeys.appLanguageOverride)
        let spanish = WalkthroughController.tour(for: .ownerManager, context: .practice).map(\.id)
        UserDefaults.standard.set(AppLanguageOverride.en.rawValue, forKey: AppSettingsKeys.appLanguageOverride)
        let english = WalkthroughController.tour(for: .ownerManager, context: .practice).map(\.id)
        XCTAssertEqual(spanish, english)

        let explainOnly = WalkthroughTourContext(hasSampleClient: true, hasRealClients: true, isPINSet: true, isBusinessProfileFilled: true)
        XCTAssertEqual(WalkthroughController.tour(for: .ownerManager, context: explainOnly).map(\.id), english)
    }

    func testCatalogKeepsEachLessonTogetherInLessonOrder() {
        XCTAssertEqual(lessonSequence(WalkthroughController.fullTour()), WalkthroughLesson.allCases)
    }

    // MARK: - Order

    func testEveryRoleWalksTheAppInScreenOrder() {
        let owner = WalkthroughController.tour(for: .ownerManager, context: .practice)
        let frontDesk = WalkthroughController.tour(for: .frontDeskGroomer, context: .practice)

        XCTAssertEqual(lessonSequence(owner), WalkthroughLesson.allCases)
        XCTAssertEqual(lessonSequence(frontDesk), [.dailyWorkflow, .clientRecords, .checkoutAndMoney])
        XCTAssertEqual(OnboardingRole.ownerManager.tourLessonOrder, lessonSequence(owner))
        XCTAssertEqual(OnboardingRole.frontDeskGroomer.tourLessonOrder, lessonSequence(frontDesk))

        // Front desk focuses on counter work; setup remains in the owner tour.
        XCTAssertFalse(frontDesk.contains { $0.surface == .insights })
        XCTAssertTrue(frontDesk.filter { $0.surface == .settings }.isEmpty)

        // Both tours: the Today cards, the Clients tab, the client list, a
        // client's profile, then the pet's Check In.
        for tour in [owner, frontDesk] {
            let ids = tour.map(\.id)
            let index = { (id: String) in ids.firstIndex(of: id) ?? .max }
            XCTAssertEqual(tour.first?.anchor, .dashKpis)
            XCTAssertEqual(index("nav.clients") + 1, index("clients.list"))
            XCTAssertLessThan(index("clients.list"), index("cd.owner"))
            XCTAssertEqual(index("cd.owner") + 1, index("cd.emergency"))
            XCTAssertLessThan(index("cd.emergency"), index("cd.pets"))
            XCTAssertEqual(index("cd.pets") + 1, index("cd.checkin"))
        }
    }

    /// The tour moves through the app once: after it leaves a screen (or a
    /// client's profile) it never comes back to it.
    func testTheTourNeverReturnsToAScreenItLeft() {
        for role in OnboardingRole.allCases {
            for context in Self.contextMatrix {
                var screens: [String] = []
                for step in WalkthroughController.tour(for: role, context: context) {
                    let screen = "\(step.surface.map { "\($0)" } ?? "none")\(step.route == .demoClientDetail ? ".detail" : "")"
                    if screens.last != screen { screens.append(screen) }
                }
                XCTAssertEqual(Set(screens).count, screens.count, "\(role) \(context): \(screens)")
            }
        }
    }

    /// No control is spotlighted twice. Quick Actions used to come back as
    /// "Check-In to Checkout", and the Dashboard row at the end of the
    /// front desk tour.
    func testNoStopRepeatsAnotherStopsSpotlight() {
        for role in OnboardingRole.allCases {
            for context in Self.contextMatrix {
                let anchors = WalkthroughController.tour(for: role, context: context).map(\.anchor)
                XCTAssertEqual(Set(anchors).count, anchors.count, "\(role) \(context): \(anchors)")
            }
        }
        XCTAssertNil(WalkthroughController.fullTour().first { $0.id == "workflow.checkout" || $0.id == "nav.dashboard" })
    }

    func testEveryTourKeepsItsLessonsTogether() {
        for role in OnboardingRole.allCases {
            for context in Self.contextMatrix {
                let steps = WalkthroughController.tour(for: role, context: context)
                let sequence = lessonSequence(steps)
                XCTAssertEqual(Set(sequence).count, sequence.count, "\(role) \(context): a lesson is split: \(sequence)")
                XCTAssertEqual(sequence, role.tourLessonOrder.filter(sequence.contains), "\(role) \(context)")
                XCTAssertEqual(WalkthroughController.lessons(for: role, context: context), sequence)
                for lesson in sequence {
                    XCTAssertEqual(
                        WalkthroughController.steps(for: lesson, role: role, context: context),
                        steps.filter { $0.lesson == lesson },
                        "\(role) \(lesson)"
                    )
                }
            }
        }
    }

    func testRolesChangeCoachTipsNotJustWhichStopsShow() {
        let owner = Dictionary(uniqueKeysWithValues: WalkthroughController.tour(for: .ownerManager, context: .practice).map { ($0.id, $0) })
        let frontDesk = Dictionary(uniqueKeysWithValues: WalkthroughController.tour(for: .frontDeskGroomer, context: .practice).map { ($0.id, $0) })
        for id in ["dash.kpis", "clients.filters", "cd.checkin"] {
            let ownerTip = owner[id]?.coachTip
            let frontDeskTip = frontDesk[id]?.coachTip
            XCTAssertNotNil(ownerTip, id)
            XCTAssertNotNil(frontDeskTip, id)
            XCTAssertNotEqual(ownerTip, frontDeskTip, id)
        }
    }

    func testCheckInStaysRightBeforeCheckOut() throws {
        for role in OnboardingRole.allCases {
            for context in Self.contextMatrix where context.hasSampleClient && context.sampleClientHasPet {
                let anchors = WalkthroughController.tour(for: role, context: context).map(\.anchor)
                let checkIn = try XCTUnwrap(anchors.firstIndex(of: .cdCheckIn), "\(role) \(context)")
                XCTAssertEqual(anchors[checkIn + 1], .cdCheckOut, "\(role) \(context)")
                XCTAssertEqual(anchors[checkIn - 1], .cdPets, "\(role) \(context)")
            }
        }
    }

    // MARK: - Stops chosen and worded from real state

    func testSecurityTipFollowsThePIN() throws {
        UserDefaults.standard.set(AppLanguageOverride.en.rawValue, forKey: AppSettingsKeys.appLanguageOverride)
        let noPIN = try XCTUnwrap(WalkthroughController.tour(for: .ownerManager, context: .practice).first { $0.id == "set.security" })
        var withPIN = WalkthroughTourContext.practice
        withPIN.isPINSet = true
        let set = try XCTUnwrap(WalkthroughController.tour(for: .ownerManager, context: withPIN).first { $0.id == "set.security" })
        XCTAssertTrue(noPIN.coachTip?.contains("skip the PIN") ?? false)
        XCTAssertFalse(set.coachTip?.contains("skip the PIN") ?? true, "A device with a PIN isn't told it can skip one.")
        XCTAssertTrue(set.coachTip?.contains("PIN is set") ?? false)
    }

    func testBusinessStopFollowsTheProfile() throws {
        UserDefaults.standard.set(AppLanguageOverride.en.rawValue, forKey: AppSettingsKeys.appLanguageOverride)
        let empty = try XCTUnwrap(WalkthroughController.tour(for: .ownerManager, context: .practice).first { $0.id == "set.business" })
        var filledContext = WalkthroughTourContext.practice
        filledContext.isBusinessProfileFilled = true
        let filled = try XCTUnwrap(WalkthroughController.tour(for: .ownerManager, context: filledContext).first { $0.id == "set.business" })
        XCTAssertNotEqual(empty.directive, filled.directive)
        XCTAssertNotEqual(empty.coachTip, filled.coachTip)
        XCTAssertTrue(empty.coachTip?.contains("receipts") ?? false)
    }

    func testBusinessProfileIsReadFromTheStore() throws {
        let container = try ModelContainer(
            for: Schema(PawtrackrSchema.models),
            configurations: [ModelConfiguration(schema: Schema(PawtrackrSchema.models), isStoredInMemoryOnly: true, cloudKitDatabase: .none)]
        )
        let context = container.mainContext
        XCTAssertFalse(WalkthroughTourContext.resolve(in: context).isBusinessProfileFilled)
        context.insert(BusinessConfig(name: "Suds & Pups"))
        try context.save()
        XCTAssertFalse(WalkthroughTourContext.resolve(in: context).isBusinessProfileFilled, "A name alone isn't a filled profile.")
        let config = try XCTUnwrap(try context.fetch(FetchDescriptor<BusinessConfig>()).first)
        config.phone = "3125550100"
        try context.save()
        let resolved = WalkthroughTourContext.resolve(in: context, isPINSet: true)
        XCTAssertTrue(resolved.isBusinessProfileFilled)
        XCTAssertTrue(resolved.isPINSet)
    }

    func testWithoutAPetTheTourSkipsPetStops() {
        let context = WalkthroughTourContext(hasSampleClient: true, hasRealClients: false, sampleClientHasPet: false, hasActiveSampleVisit: false)
        for role in OnboardingRole.allCases {
            let steps = WalkthroughController.tour(for: role, context: context)
            XCTAssertFalse(steps.contains(where: \.needsTourPet), "\(role)")
            XCTAssertTrue(steps.contains { $0.anchor == .cdAddPet }, "\(role): adding a pet is still taught")
            XCTAssertTrue(steps.contains { $0.anchor == .cdOwner }, "\(role)")
        }
    }

    func testLookOnlyReplayWithoutAVisitInSessionDropsCheckoutScreens() {
        let context = WalkthroughTourContext(hasSampleClient: true, hasRealClients: true, hasActiveSampleVisit: false)
        for role in OnboardingRole.allCases {
            let steps = WalkthroughController.tour(for: role, context: context)
            XCTAssertFalse(steps.contains { $0.presents == .checkout }, "\(role)")
            XCTAssertTrue(steps.contains { $0.anchor == .cdCheckOut }, "\(role): the Check Out button is still explained")
        }
        // Hands-on, check-in happens first in the same lesson, so checkout can open.
        let practice = WalkthroughTourContext(hasSampleClient: true, hasRealClients: false, hasActiveSampleVisit: false)
        let lesson = WalkthroughController.steps(for: .checkoutAndMoney, role: .frontDeskGroomer, context: practice)
        XCTAssertTrue(lesson.contains { $0.presents == .checkout })
        XCTAssertLessThan(
            lesson.firstIndex { $0.anchor == .cdCheckIn } ?? .max,
            lesson.firstIndex { $0.anchor == .cdCheckOut } ?? .min
        )
    }

    // MARK: - Skip rules at runtime

    func testNeedsAttentionIsSkippedWhenItsSectionIsMissing() {
        let controller = makeController()
        let steps = WalkthroughController.tour(for: .frontDeskGroomer, context: .practice)
        controller.start(steps, at: "dash.attention")
        XCTAssertEqual(controller.currentStep?.id, "dash.attention")

        let count = controller.stepCount

        controller.checkTargets()

        XCTAssertEqual(controller.currentStep?.id, "dash.recent", "No pet is due, so the stop is skipped.")
        XCTAssertEqual(controller.stepCount, count - 1, "The counter no longer counts it.")
        controller.goBack()
        XCTAssertEqual(controller.currentStep?.id, "dash.quick", "Back doesn't land on it again.")
    }

    func testNeedsAttentionStaysWhenItsSectionShows() {
        let controller = makeController()
        controller.start(WalkthroughController.tour(for: .frontDeskGroomer, context: .practice), at: "dash.attention")
        controller.noteStepShown("dash.attention", hasTarget: true)
        controller.checkTargets()
        XCTAssertEqual(controller.currentStep?.id, "dash.attention")
        XCTAssertFalse(controller.isCurrentStepOrphaned)
    }

    func testAMissingSectionIsSkippedInTheDirectionTheUserWasGoingAndOnlyOnce() {
        let controller = makeController()
        controller.start(WalkthroughController.tour(for: .frontDeskGroomer, context: .practice), at: "dash.recent")
        controller.noteStepShown("dash.recent", hasTarget: true)
        controller.goBack()
        XCTAssertEqual(controller.currentStep?.id, "dash.attention")
        controller.checkTargets()
        XCTAssertEqual(controller.currentStep?.id, "dash.quick", "Going Back past a missing section keeps going back.")
        controller.advance()
        XCTAssertEqual(controller.currentStep?.id, "dash.recent", "Next doesn't wait on the missing section a second time.")
    }

    func testTheLastMissingStopOfALessonStillFinishesTheLesson() {
        let controller = makeController()
        var progress = WalkthroughProgress()
        controller.onProgress = { progress = progress.recording($0) }
        // The owner's dashboard ends on Getting Started, hidden once set up.
        controller.start(WalkthroughController.tour(for: .ownerManager, context: .practice), at: WalkthroughStepID.setupChecklist)
        controller.checkTargets()
        XCTAssertEqual(controller.currentStep?.id, "nav.clients")
        XCTAssertTrue(progress.isComplete(.dailyWorkflow))
    }

    func testARepeatedTapCannotSkipOrRewindAStop() {
        let controller = makeController()
        let steps = WalkthroughController.tour(for: .frontDeskGroomer, context: .practice)
        controller.start(steps)

        // A double-click on Next: both taps come from the first stop's bubble.
        controller.advance(from: steps[0].id)
        controller.advance(from: steps[0].id)
        XCTAssertEqual(controller.currentStep?.id, steps[1].id)

        controller.advance(from: steps[1].id)
        controller.goBack(from: steps[2].id)
        controller.goBack(from: steps[2].id)
        XCTAssertEqual(controller.currentStep?.id, steps[1].id)
    }

    func testRestartingOrReappearingDoesNotResetARunningTour() {
        let controller = makeController()
        let steps = WalkthroughController.tour(for: .frontDeskGroomer, context: .practice)
        controller.start(steps)
        controller.advance()
        controller.advance()
        // A screen appearing again asks to start: the running tour keeps its place.
        controller.start(steps)
        XCTAssertEqual(controller.currentStep?.id, steps[2].id)
    }

    func testSortStopIsSkippedWithAnEmptyClientList() {
        let controller = makeController()
        controller.start(WalkthroughController.tour(for: .frontDeskGroomer, context: .practice), at: "clients.sort")
        controller.checkTargets()
        XCTAssertEqual(controller.currentStep?.id, "nc.owner")
    }

    // MARK: - Hands-on stops

    func testHandsOnStopsMoveOnWhenTheRealActionHappens() {
        let cases: [(String, WalkthroughTrigger, String)] = [
            ("clients.sort", .clientSortChanged, "nc.owner"),
            ("cd.emergency_badges", .emergencyContactEditorClosed, "cd.loyalty"),
            ("cd.addpet", .petAdded, "cd.gender_dots")
        ]
        for (stepID, trigger, nextID) in cases {
            let controller = makeController()
            controller.start(WalkthroughController.tour(for: .frontDeskGroomer, context: .practice), at: stepID)
            XCTAssertTrue(controller.currentStepShowsNext, "\(stepID): Next stays available")
            XCTAssertFalse(controller.observe(.petAdded == trigger ? .clientSortChanged : .petAdded), "\(stepID): another action doesn't count")
            XCTAssertEqual(controller.currentStep?.id, stepID)
            XCTAssertTrue(controller.observe(trigger), stepID)
            XCTAssertEqual(controller.currentStep?.id, nextID, stepID)
        }
    }

    func testLookOnlyStopsIgnoreTheRealAction() {
        let lookOnly = WalkthroughTourContext(hasSampleClient: true, hasRealClients: true)
        let controller = makeController()
        controller.start(WalkthroughController.tour(for: .ownerManager, context: lookOnly), at: "clients.sort")
        XCTAssertFalse(controller.observe(.clientSortChanged))
        XCTAssertEqual(controller.currentStep?.id, "clients.sort")
    }

    func testHandsOnStopsNeverDeadEnd() {
        for role in OnboardingRole.allCases {
            for context in Self.contextMatrix {
                let steps = WalkthroughController.tour(for: role, context: context)
                for step in steps where step.requiresTargetAction {
                    // The target never appears: Next shows.
                    let missing = makeController()
                    missing.start(steps, at: step.id)
                    XCTAssertFalse(missing.currentStepShowsNext, "\(role) \(step.id)")
                    missing.noteStepShown(step.id, hasTarget: false)
                    missing.checkTargets()
                    XCTAssertTrue(missing.currentStepShowsNext, "\(role) \(step.id): no target, so Next shows")

                    // The target is there but the action can't happen.
                    let blocked = makeController()
                    blocked.start(steps, at: step.id)
                    blocked.noteStepShown(step.id, hasTarget: true)
                    blocked.checkTargets()
                    XCTAssertFalse(blocked.currentStepShowsNext, "\(role) \(step.id)")
                    blocked.releaseActionRequirement(reason: "test")
                    XCTAssertTrue(blocked.currentStepShowsNext, "\(role) \(step.id)")
                }
                if context.isExplainOnly {
                    XCTAssertFalse(steps.contains { $0.requiresTargetAction || $0.allowsTargetInteraction || $0.advancesOn != nil }, "\(role)")
                }
            }
        }
    }

    func testEveryStopIsDrawnEvenWhenItsScreenNeverShowsIt() {
        for role in OnboardingRole.allCases {
            for context in Self.contextMatrix {
                let steps = WalkthroughController.tour(for: role, context: context)
                for step in steps where !step.skipsWhenTargetMissing {
                    let controller = makeController()
                    controller.start(steps, at: step.id)
                    controller.checkTargets()
                    XCTAssertTrue(controller.isCurrentStepOrphaned, "\(role) \(step.id)")
                    for rootScope in [WalkthroughOverlayScope.all, .navigation] {
                        XCTAssertTrue(
                            WalkthroughOverlayScope.hostDraws(step, presenting: nil, scope: rootScope, adoptsOrphanedSteps: true, isOrphaned: true),
                            "\(role) \(step.id): the root overlay draws it"
                        )
                    }
                }
            }
        }
    }

    func testTheStepsOwnOverlayTakesOverFromTheRoot() {
        let controller = makeController()
        let steps = WalkthroughController.tour(for: .frontDeskGroomer, context: .practice)
        controller.start(steps, at: "co.services")
        controller.checkTargets()
        XCTAssertTrue(controller.isCurrentStepOrphaned)
        controller.noteStepShown("co.services", hasTarget: false, adopted: true)
        XCTAssertTrue(controller.isCurrentStepOrphaned, "The root keeps drawing it.")
        controller.noteStepShown("co.services", hasTarget: true)
        XCTAssertFalse(controller.isCurrentStepOrphaned, "Checkout opened late: only its overlay draws the step.")
        controller.advance()
        XCTAssertFalse(controller.isCurrentStepOrphaned)
    }

    func testOnlyTheStepsHomeOverlayDrawsItNormally() {
        let step = WalkthroughController.fullTour().first { $0.anchor == .coServices }!
        XCTAssertFalse(WalkthroughOverlayScope.hostDraws(step, presenting: nil, scope: .all, adoptsOrphanedSteps: true, isOrphaned: false))
        XCTAssertTrue(WalkthroughOverlayScope.hostDraws(step, presenting: .checkout, scope: .all, adoptsOrphanedSteps: false, isOrphaned: false))
        let gender = WalkthroughController.fullTour().first { $0.anchor == .petGenderDots }!
        XCTAssertTrue(WalkthroughOverlayScope.detailContent.handles(gender))
        XCTAssertFalse(WalkthroughOverlayScope.rootContent.handles(gender), "The detail column must not draw it a second time.")
    }

    // MARK: - Progress

    func testProgressRecordsStopsAndFinishedLessons() {
        let controller = makeController()
        var progress = WalkthroughProgress()
        controller.onProgress = { progress = progress.recording($0) }
        let steps = WalkthroughController.tour(for: .frontDeskGroomer, context: .practice)
        controller.start(steps)
        let firstLessonCount = steps.prefix { $0.lesson == .dailyWorkflow }.count

        for _ in 0..<(firstLessonCount - 1) { controller.advance() }
        XCTAssertFalse(progress.isComplete(.dailyWorkflow))
        XCTAssertEqual(progress.lastCompletedStepID, steps[firstLessonCount - 2].id)

        controller.advance()
        XCTAssertTrue(progress.isComplete(.dailyWorkflow))
        XCTAssertEqual(progress.lastCompletedStepID, steps[firstLessonCount - 1].id)
        XCTAssertEqual(progress.continuePosition(in: OnboardingRole.frontDeskGroomer.tourLessonOrder)?.lesson, 2)
        XCTAssertEqual(progress.continuePosition(in: OnboardingRole.frontDeskGroomer.tourLessonOrder)?.of, 3)

        controller.skip()
        XCTAssertTrue(progress.isComplete(.dailyWorkflow), "Skipping keeps what was finished.")
        XCTAssertFalse(progress.isComplete(.clientRecords))
    }

    func testCreatingAClientRecordsTheFormStops() {
        let controller = makeController()
        var events: [WalkthroughProgressEvent] = []
        controller.onProgress = { events.append($0) }
        controller.start(WalkthroughController.tour(for: .ownerManager, context: .practice), at: "nc.owner")
        controller.completePresentation(.newClient)
        XCTAssertEqual(events.map(\.stepID), ["nc.owner", "nc.pets", "nc.save"])
        XCTAssertEqual(controller.currentStep?.id, "cd.owner")
    }

    func testProgressIsSavedAndReadBack() {
        var progress = WalkthroughProgress()
        progress = progress.recording(WalkthroughProgressEvent(stepID: "clients.filters", lesson: .dailyWorkflow, completesLesson: true))
        progress = progress.recording(WalkthroughProgressEvent(stepID: "nc.pets", lesson: .clientRecords, completesLesson: false))

        AppSettings.storeTourProgress(progress, in: defaults)
        XCTAssertEqual(AppSettings.loadTourProgress(from: defaults), progress)
        XCTAssertEqual(defaults.stringArray(forKey: AppSettingsKeys.tourCompletedLessons), ["dailyWorkflow"])
        XCTAssertEqual(defaults.string(forKey: AppSettingsKeys.tourLastCompletedStepID), "nc.pets")

        AppSettings.storeTourProgress(WalkthroughProgress(), in: defaults)
        XCTAssertEqual(AppSettings.loadTourProgress(from: defaults), WalkthroughProgress())
        XCTAssertNil(defaults.object(forKey: AppSettingsKeys.tourCompletedLessons))

        defaults.set(["dailyWorkflow", "someRetiredLesson"], forKey: AppSettingsKeys.tourCompletedLessons)
        XCTAssertEqual(AppSettings.loadTourProgress(from: defaults).completedLessons, [.dailyWorkflow], "Unknown lessons are ignored.")
    }

    func testContinueResumesMidLessonThenAtTheNextLesson() {
        let steps = WalkthroughController.tour(for: .frontDeskGroomer, context: .practice)
        XCTAssertEqual(WalkthroughProgress().resumeStepID(in: steps), steps.first?.id)

        var progress = WalkthroughProgress()
        let dashboard = steps.prefix(while: { $0.lesson == .dailyWorkflow })
        for step in dashboard {
            progress = progress.recording(WalkthroughProgressEvent(stepID: step.id, lesson: step.lesson, completesLesson: step.id == dashboard.last?.id))
        }
        let clientRecordsStart = steps.first { $0.lesson == .clientRecords }?.id
        XCTAssertEqual(clientRecordsStart, "nav.clients")
        XCTAssertEqual(progress.resumeStepID(in: steps), clientRecordsStart)

        progress = progress.recording(WalkthroughProgressEvent(stepID: "clients.list", lesson: .clientRecords, completesLesson: false))
        XCTAssertEqual(progress.resumeStepID(in: steps), "clients.filters", "Continue picks up mid-lesson.")

        // A lesson replayed out of order doesn't pull Continue forward.
        var outOfOrder = WalkthroughProgress()
        outOfOrder = outOfOrder.recording(WalkthroughProgressEvent(stepID: "set.data", lesson: .dataOwnership, completesLesson: true))
        XCTAssertEqual(outOfOrder.resumeStepID(in: steps), steps.first?.id)
        XCTAssertEqual(outOfOrder.continuePosition(in: OnboardingRole.frontDeskGroomer.tourLessonOrder)?.lesson, 1)

        let allDone = WalkthroughProgress(completedLessons: Set(WalkthroughLesson.allCases), lastCompletedStepID: "cd.history")
        XCTAssertNil(allDone.resumeStepID(in: steps))
        XCTAssertNil(allDone.continuePosition(in: OnboardingRole.ownerManager.tourLessonOrder))
    }

    func testStartAtAStepIDUsesItOrFallsBackToTheStart() {
        let steps = WalkthroughController.tour(for: .ownerManager, context: .practice)
        let controller = makeController()
        controller.start(steps, at: "set.data")
        XCTAssertEqual(controller.currentStep?.id, "set.data")
        controller.restart(steps, at: "retired.step")
        XCTAssertEqual(controller.currentIndex, 0)
        controller.restart(WalkthroughController.steps(for: .businessInsights, role: .ownerManager, context: .practice))
        XCTAssertEqual(controller.currentStep?.id, "nav.insights")
        XCTAssertTrue(controller.steps.allSatisfy { $0.lesson == .businessInsights })
    }

    func testSavedProgressDrivesTheSettingsLabel() {
        let settings = AppSettings()
        let saved = settings.tourProgress
        defer { settings.tourProgress = saved }

        settings.resetTourProgress()
        XCTAssertEqual(settings.tourProgress, WalkthroughProgress())
        settings.recordTourProgress(WalkthroughProgressEvent(stepID: "dash.checklist", lesson: .dailyWorkflow, completesLesson: true))
        XCTAssertEqual(AppSettings.loadTourProgress(), settings.tourProgress, "Written through to UserDefaults.")
        let owner = settings.tourProgress.continuePosition(in: OnboardingRole.ownerManager.tourLessonOrder)
        let frontDesk = settings.tourProgress.continuePosition(in: OnboardingRole.frontDeskGroomer.tourLessonOrder)
        XCTAssertEqual(owner?.lesson, 2)
        XCTAssertEqual(owner?.of, 6)
        XCTAssertEqual(frontDesk?.lesson, 2)
        XCTAssertEqual(frontDesk?.of, 3)
    }

    // MARK: - Anchors

    private enum Home {
        /// Sidebar row (iPad/Mac) and the tab strip (iPhone).
        case navigation
        /// A column's root screen: Dashboard, Clients, Insights.
        case rootContent
        /// A pushed screen: client details, Settings sections.
        case detail
        /// Inside a sheet the tour opens.
        case sheet(WalkthroughPresentation)
    }

    /// Where each anchor is attached, and the file that attaches it.
    private static let homes: [WalkthroughAnchorID: (Home, String)] = [
        .dashboard: (.navigation, "Pawtrackr/App/Navigation/SidebarView.swift"),
        .clients: (.navigation, "Pawtrackr/App/Navigation/SidebarView.swift"),
        .insights: (.navigation, "Pawtrackr/App/Navigation/SidebarView.swift"),
        .settings: (.navigation, "Pawtrackr/App/Navigation/SidebarView.swift"),
        .dashKpis: (.rootContent, "Pawtrackr/Features/Dashboard/DashboardView.swift"),
        .dashQuickActions: (.rootContent, "Pawtrackr/Features/Dashboard/DashboardView.swift"),
        .dashNeedsAttention: (.rootContent, "Pawtrackr/Features/Dashboard/DashboardView.swift"),
        .dashRecentClients: (.rootContent, "Pawtrackr/Features/Dashboard/DashboardView.swift"),
        .dashRevenue: (.rootContent, "Pawtrackr/Features/Dashboard/DashboardView.swift"),
        .setupChecklist: (.rootContent, "Pawtrackr/Features/Dashboard/DashboardView.swift"),
        .clientList: (.rootContent, "Pawtrackr/Features/Clients/ClientsView.swift"),
        .clientFilters: (.rootContent, "Pawtrackr/Features/Clients/ClientsView.swift"),
        .clientSort: (.rootContent, "Pawtrackr/Features/Clients/ClientsView.swift"),
        .insKpis: (.rootContent, "Pawtrackr/Features/Insights/InsightsView.swift"),
        .insRevenue: (.rootContent, "Pawtrackr/Features/Insights/InsightsView.swift"),
        .insMonthly: (.rootContent, "Pawtrackr/Features/Insights/InsightsView.swift"),
        .insServices: (.rootContent, "Pawtrackr/Features/Insights/InsightsView.swift"),
        .insPaymentMix: (.rootContent, "Pawtrackr/Features/Insights/InsightsView.swift"),
        .insCategory: (.rootContent, "Pawtrackr/Features/Insights/InsightsView.swift"),
        .ncOwner: (.sheet(.newClient), "Pawtrackr/Features/Clients/NewClientSheet.swift"),
        .ncPets: (.sheet(.newClient), "Pawtrackr/Features/Clients/NewClientSheet.swift"),
        .ncSave: (.sheet(.newClient), "Pawtrackr/Features/Clients/NewClientSheet.swift"),
        .cdOwner: (.detail, "Pawtrackr/Features/Clients/ClientDetailView.swift"),
        .cdEmergency: (.detail, "Pawtrackr/Features/Clients/ClientDetailView.swift"),
        .cdLoyalty: (.detail, "Pawtrackr/Features/Clients/ClientDetailView.swift"),
        .emergencyContactBadges: (.detail, "Pawtrackr/UI/Components/EmergencyContactSummaryCard.swift"),
        .petGenderDots: (.detail, "Pawtrackr/Features/Clients/ClientDetailView.swift"),
        .cdPets: (.detail, "Pawtrackr/Features/Clients/ClientDetailView.swift"),
        .cdAddPet: (.detail, "Pawtrackr/Features/Clients/ClientDetailView.swift"),
        .cdCheckIn: (.detail, "Pawtrackr/Features/Clients/ClientDetailView.swift"),
        .cdCheckOut: (.detail, "Pawtrackr/Features/Clients/ClientDetailView.swift"),
        .cdPetHistory: (.detail, "Pawtrackr/Features/Clients/ClientDetailView.swift"),
        .cdHistory: (.detail, "Pawtrackr/Features/Clients/ClientDetailView.swift"),
        .coServices: (.sheet(.checkout), "Pawtrackr/Features/Checkout/CheckoutView.swift"),
        .coDetails: (.sheet(.checkout), "Pawtrackr/Features/Checkout/CheckoutView.swift"),
        .coPayment: (.sheet(.checkout), "Pawtrackr/Features/Checkout/CheckoutView.swift"),
        .coReview: (.sheet(.checkout), "Pawtrackr/Features/Checkout/CheckoutView.swift"),
        .coConfirm: (.sheet(.checkout), "Pawtrackr/Features/Checkout/CheckoutView.swift"),
        .setBusiness: (.detail, "Pawtrackr/Features/Settings/SettingsView.swift"),
        .setLoyalty: (.detail, "Pawtrackr/Features/Settings/SettingsView.swift"),
        .setSecurity: (.detail, "Pawtrackr/Features/Settings/SettingsView.swift"),
        .setData: (.detail, "Pawtrackr/Features/Settings/SettingsView.swift"),
        .setAbout: (.detail, "Pawtrackr/Features/Settings/SettingsView.swift"),
        .setStartFresh: (.detail, "Pawtrackr/Features/Settings/SettingsView.swift"),
        .loyaltySimulator: (.detail, "Pawtrackr/Features/Loyalty/LoyaltyManagementView.swift")
    ]

    private func source(_ relativePath: String) throws -> String {
        var root = URL(fileURLWithPath: #filePath)
        while !FileManager.default.fileExists(atPath: root.appendingPathComponent("Pawtrackr.xcodeproj").path) {
            let parent = root.deletingLastPathComponent()
            guard parent.path != root.path else { throw XCTSkip("Repository sources aren't available.") }
            root = parent
        }
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    func testEveryStopsAnchorIsAttachedWhereItsOverlayCanSeeIt() throws {
        let anchors = Set(WalkthroughController.fullTour().map(\.anchor))
        for anchor in anchors.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let (home, file) = Self.homes[anchor] else {
                XCTFail("\(anchor) has no known home. Add it to the table.")
                continue
            }
            let steps = WalkthroughController.fullTour().filter { $0.anchor == anchor }
            let text = try source(file)
            let literal = text.range(of: #"walkthrough(Target|Anchor)\(\.\#(anchor.rawValue)[,)]"#, options: .regularExpression) != nil
            let mapped = text.contains("return .\(anchor.rawValue)")
            XCTAssertTrue(literal || mapped, "\(anchor) isn't attached in \(file)")

            for step in steps {
                switch home {
                case .navigation:
                    XCTAssertTrue(WalkthroughOverlayScope.navigation.handles(step), "\(anchor)")
                    XCTAssertTrue(WalkthroughOverlayScope.all.handles(step), "\(anchor)")
                    if case .tabBarItem = step.fallback {} else {
                        XCTFail("\(anchor) needs the iPhone tab-bar fallback")
                    }
                    XCTAssertNil(step.presents)
                case .rootContent:
                    XCTAssertTrue(WalkthroughOverlayScope.rootContent.handles(step), "\(anchor)")
                    XCTAssertFalse(WalkthroughOverlayScope.detailContent.handles(step), "\(anchor) would be drawn twice")
                    XCTAssertNil(step.presents)
                case .detail:
                    XCTAssertTrue(WalkthroughOverlayScope.detailContent.handles(step), "\(anchor) isn't drawn on iPad and Mac")
                    XCTAssertFalse(WalkthroughOverlayScope.rootContent.handles(step), "\(anchor) would be drawn twice")
                    XCTAssertNil(step.presents)
                case .sheet(let presentation):
                    XCTAssertEqual(step.presents, presentation, "\(anchor)")
                }
            }
        }
        // The sidebar maps rows to anchors, and the iPhone tab strip uses the same mapping.
        XCTAssertTrue(try source("Pawtrackr/App/Navigation/SidebarView.swift").contains("walkthroughAnchor(item.walkthroughAnchorID)"))
        XCTAssertTrue(try source("Pawtrackr/App/ContentView.swift").contains("walkthroughAnchor(item.walkthroughAnchorID)"))
    }

    func testClientDetailScrollsToEveryDetailStop() {
        let detailStops = WalkthroughController.fullTour().filter { $0.route == .demoClientDetail && $0.presents == nil }
        for step in detailStops {
            XCTAssertTrue(ClientDetailView.walkthroughAnchors.contains(step.anchor), "\(step.anchor) is never scrolled into view")
        }
    }

    func testGenderDotsAnchorOnlyOnePetOnClientDetails() throws {
        let dashboard = try source("Pawtrackr/Features/Dashboard/DashboardView.swift")
        XCTAssertFalse(dashboard.contains("walkthroughTarget(.petGenderDots)"), "A second gender-dot anchor competes with the one on client details.")
        let detail = try source("Pawtrackr/Features/Clients/ClientDetailView.swift")
        XCTAssertFalse(detail.contains("walkthroughTarget(.petGenderDots)\n"), "Every pet row would register the same anchor.")
        XCTAssertFalse(detail.contains(".walkthroughTarget(.cdEmergency)\n                        .walkthroughTarget(.emergencyContactBadges)"))
    }

    // MARK: - Copy

    func testEveryCopyVariantStaysShortAndPlain() {
        for language in [AppLanguageOverride.en, .es] {
            UserDefaults.standard.set(language.rawValue, forKey: AppSettingsKeys.appLanguageOverride)
            var checked = Set<String>()
            for role in OnboardingRole.allCases {
                let contexts = Self.contextMatrix
                for context in contexts {
                    for step in WalkthroughController.tour(for: role, context: context) {
                        let key = [step.id, step.directive, step.purpose, step.coachTip ?? ""].joined(separator: "|")
                        guard checked.insert(key).inserted else { continue }
                        XCTAssertLessThanOrEqual(step.directive.count, 86, "\(language) \(step.id): \(step.directive)")
                        XCTAssertLessThanOrEqual(step.purpose.count, 190, "\(language) \(step.id): \(step.purpose)")
                        XCTAssertLessThanOrEqual(step.coachTip?.count ?? 0, 150, "\(language) \(step.id): \(step.coachTip ?? "")")
                        for text in [step.title, step.directive, step.purpose] + [step.coachTip].compactMap(\.self) {
                            XCTAssertFalse(text.contains(";"), "\(language) \(step.id): \(text)")
                            XCTAssertFalse(text.contains(" — "), "\(language) \(step.id): \(text)")
                            XCTAssertFalse(text.hasPrefix("tour."), "\(language) \(step.id): missing key \(text)")
                            if language == .es {
                                XCTAssertFalse(text.localizedCaseInsensitiveContains("walkthrough"), "\(step.id): \(text)")
                            }
                        }
                    }
                }
            }
            XCTAssertGreaterThan(checked.count, WalkthroughController.fullTour().count)
        }
    }

    func testCopyMatchesTheScreens() throws {
        UserDefaults.standard.set(AppLanguageOverride.en.rawValue, forKey: AppSettingsKeys.appLanguageOverride)
        let steps = Dictionary(uniqueKeysWithValues: WalkthroughController.fullTour().map { ($0.id, $0) })

        // Quick Actions has New Client and Check Out, nothing else.
        let quick = try XCTUnwrap(steps["dash.quick"]).purpose
        XCTAssertTrue(quick.contains("New Client") && quick.contains("Check Out"), quick)
        XCTAssertFalse(quick.contains("Reports") || quick.contains("check a pet in"), quick)

        // The tip is part of the total, not kept apart.
        let paymentTip = try XCTUnwrap(steps["co.payment"]?.coachTip)
        XCTAssertFalse(paymentTip.contains("separate"), paymentTip)
        XCTAssertTrue(paymentTip.contains("total"), paymentTip)

        // The emergency card's actions.
        let emergency = try XCTUnwrap(steps["cd.emergency"]).purpose
        for action in ["Call", "Message", "Copy Phone", "Edit", "Delete", "Missing:"] {
            XCTAssertTrue(emergency.contains(action), "\(action): \(emergency)")
        }

        // What the gender colors mean, and where they show.
        let gender = try XCTUnwrap(steps["cd.gender_dots"])
        XCTAssertTrue(gender.directive.contains("Blue") && gender.directive.contains("male") && gender.directive.contains("pink"))
        XCTAssertTrue(gender.purpose.contains("client cards"))

        // The filter chips by their real names.
        let filters = try XCTUnwrap(steps["clients.filters"]).directive
        for chip in ClientsViewModel.Filter.allCases {
            XCTAssertTrue(filters.contains(chip.displayName), "\(chip.displayName): \(filters)")
        }
        XCTAssertFalse(filters.contains("overdue"))

        // Last-name-first in the list.
        let sortTip = try XCTUnwrap(steps["clients.sort"]?.coachTip)
        XCTAssertTrue(sortTip.contains("Doe Jane"), sortTip)

        // The catalog cannot direct users to removed cloud screens.
        XCTAssertNil(steps["set.icloud"])
        XCTAssertNil(steps["set.devices"])
    }
}
