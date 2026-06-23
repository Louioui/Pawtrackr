import XCTest
import SwiftData
import SwiftUI
@testable import Pawtrackr

@MainActor
final class OnboardingViewModelTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        try super.setUpWithError()
        resetAppSettingsDefaults()

        let schema = Schema(PawtrackrSchema.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [config])
        context = container.mainContext
    }

    override func tearDownWithError() throws {
        container = nil
        context = nil
        resetAppSettingsDefaults()
        unsetenv("PAWTRACKR_UI_TESTING")
        unsetenv("PAWTRACKR_UI_START_WALKTHROUGH")
        try super.tearDownWithError()
    }

    func testRegionalStepAllowsBlankEmailButRejectsInvalidEmail() {
        let viewModel = OnboardingViewModel(modelContext: context, appSettings: AppSettings())
        viewModel.currentStep = .regional

        viewModel.email = ""
        XCTAssertTrue(viewModel.canGoNext)

        viewModel.email = "invalid-email"
        XCTAssertFalse(viewModel.canGoNext)
        XCTAssertEqual(viewModel.regionalValidationMessage, "Enter a valid email address (e.g., hello@business.com).")

        viewModel.email = "owner@example.com"
        XCTAssertTrue(viewModel.canGoNext)
        XCTAssertNil(viewModel.regionalValidationMessage)
    }

    func testSecurityStepRequiresFourDigitNumericMatch() {
        let viewModel = OnboardingViewModel(modelContext: context, appSettings: AppSettings())
        viewModel.currentStep = .security

        viewModel.pin = "12"
        viewModel.confirmPin = "12"
        XCTAssertFalse(viewModel.canGoNext)

        viewModel.pin = "12ab"
        viewModel.confirmPin = "12ab"
        XCTAssertFalse(viewModel.canGoNext)
        XCTAssertEqual(viewModel.securityValidationMessage, "PIN must use numbers only.")

        viewModel.pin = "4826"
        viewModel.confirmPin = "4827"
        XCTAssertFalse(viewModel.canGoNext)
        XCTAssertEqual(viewModel.securityValidationMessage, "PINs do not match.")

        viewModel.confirmPin = "4826"
        XCTAssertTrue(viewModel.canGoNext)
        XCTAssertNil(viewModel.securityValidationMessage)
    }

    func testFinishPersistsBusinessConfigAndSettings() async throws {
        let settings = AppSettings()
        let viewModel = OnboardingViewModel(modelContext: context, appSettings: settings)

        viewModel.name = "Northside Grooming"
        viewModel.email = "hello@northside.example"
        viewModel.phone = "3125550188"
        viewModel.address = "123 Paw Street"
        viewModel.currencySymbol = "€"
        viewModel.lockOnBackgroundEnabled = false
        viewModel.autoLockAfterInactivityEnabled = true
        viewModel.biometricsEnabled = false
        viewModel.pin = "4826"
        viewModel.confirmPin = "4826"

        var completed = false
        let task = await viewModel.finish(seedSampleData: false) {
            completed = true
        }
        _ = await task?.result

        XCTAssertTrue(completed)
        XCTAssertNil(viewModel.saveError)
        XCTAssertEqual(settings.businessName, "Northside Grooming")
        XCTAssertEqual(settings.currencySymbol, "€")
        XCTAssertFalse(settings.autoLockOnBackground)
        XCTAssertTrue(settings.autoLockAfterInactivity)
        XCTAssertTrue(settings.validatePIN("4826"))

        let configs = try context.fetch(FetchDescriptor<BusinessConfig>())
        XCTAssertEqual(configs.first?.name, "Northside Grooming")
        XCTAssertEqual(configs.first?.email, "hello@northside.example")
        XCTAssertEqual(configs.first?.phone, "3125550188")
        XCTAssertEqual(configs.first?.address, "123 Paw Street")
        XCTAssertEqual(configs.first?.isSetupComplete, true)
    }

    func testFinishWithDemoDataSeedsStarterRecords() async throws {
        let settings = AppSettings()
        let viewModel = OnboardingViewModel(modelContext: context, appSettings: settings)

        viewModel.name = "Harbor Grooming"
        viewModel.currencySymbol = "$"
        viewModel.pin = "4826"
        viewModel.confirmPin = "4826"

        let task = await viewModel.finish(seedSampleData: true) { }
        _ = await task?.result

        XCTAssertNil(viewModel.saveError)
        XCTAssertTrue(settings.hasConfiguredPrices)
        XCTAssertTrue(settings.hasAddedFirstClient)
        XCTAssertTrue(settings.hasCompletedFirstVisit)

        // After fix #2 the demo seeder runs on a background context, so the
        // newly inserted records live on the shared store but may not be in the
        // main context's row cache yet — re-fetch with a fresh background context
        // to verify they actually persisted.
        let bgContext = ModelContext(container)
        XCTAssertGreaterThan(try bgContext.fetchCount(FetchDescriptor<Client>()), 0)
        XCTAssertGreaterThan(try bgContext.fetchCount(FetchDescriptor<Visit>()), 0)
        XCTAssertGreaterThan(try bgContext.fetchCount(FetchDescriptor<Service>()), 0)
    }

    // MARK: - Navigation

    func testNextStep_ProgressesThroughAllStepsWhenValid() {
        let viewModel = OnboardingViewModel(modelContext: context, appSettings: AppSettings())
        XCTAssertEqual(viewModel.currentStep, .welcome)

        viewModel.nextStep()
        XCTAssertEqual(viewModel.currentStep, .businessProfile)

        // Business profile blocks until name is set.
        viewModel.nextStep()
        XCTAssertEqual(viewModel.currentStep, .businessProfile, "Should stay on businessProfile when name is empty.")

        viewModel.name = "Test Grooming"
        viewModel.nextStep()
        XCTAssertEqual(viewModel.currentStep, .regional)

        // Regional accepts blank email.
        viewModel.nextStep()
        XCTAssertEqual(viewModel.currentStep, .security)

        // Security blocks until PINs are valid and matching.
        viewModel.nextStep()
        XCTAssertEqual(viewModel.currentStep, .security)

        viewModel.pin = "1234"
        viewModel.confirmPin = "1234"
        viewModel.nextStep()
        XCTAssertEqual(viewModel.currentStep, .permissions)

        viewModel.nextStep()
        XCTAssertEqual(viewModel.currentStep, .warmStart)

        // Warm start is the last step — nextStep beyond it should be a no-op.
        viewModel.nextStep()
        XCTAssertEqual(viewModel.currentStep, .warmStart)
    }

    func testPreviousStep_GoesBackButStopsAtWelcome() {
        let viewModel = OnboardingViewModel(modelContext: context, appSettings: AppSettings())
        viewModel.currentStep = .regional

        viewModel.previousStep()
        XCTAssertEqual(viewModel.currentStep, .businessProfile)

        viewModel.previousStep()
        XCTAssertEqual(viewModel.currentStep, .welcome)

        viewModel.previousStep()
        XCTAssertEqual(viewModel.currentStep, .welcome, "previousStep at welcome should be a no-op.")
    }

    func testGoToStep_OnlyPermitsBackwardsNavigation() {
        let viewModel = OnboardingViewModel(modelContext: context, appSettings: AppSettings())
        viewModel.currentStep = .security

        viewModel.goToStep(.businessProfile)
        XCTAssertEqual(viewModel.currentStep, .businessProfile, "Backwards jump should succeed.")

        viewModel.goToStep(.permissions)
        XCTAssertEqual(viewModel.currentStep, .businessProfile, "Forward jump should be ignored.")

        viewModel.goToStep(.businessProfile)
        XCTAssertEqual(viewModel.currentStep, .businessProfile, "Same-step jump should be a no-op.")
    }

    func testPrimaryActionTitle_VariesByStep() {
        let viewModel = OnboardingViewModel(modelContext: context, appSettings: AppSettings())

        viewModel.currentStep = .welcome
        XCTAssertEqual(viewModel.primaryActionTitle, "Get Started")

        viewModel.currentStep = .businessProfile
        XCTAssertEqual(viewModel.primaryActionTitle, "Continue")

        viewModel.currentStep = .permissions
        XCTAssertEqual(viewModel.primaryActionTitle, "Review Setup")

        viewModel.currentStep = .warmStart
        XCTAssertEqual(viewModel.primaryActionTitle, "Continue")
    }

    func testFullWalkthroughTeachesCompleteNewUserCurriculum() throws {
        let steps = WalkthroughController.fullTour()
        let lessons = Set(steps.map(\.lesson))

        XCTAssertGreaterThanOrEqual(steps.count, 24)
        XCTAssertTrue(lessons.isSuperset(of: [
            .appMap,
            .dailyWorkflow,
            .clientRecords,
            .checkoutAndMoney,
            .businessInsights,
            .settingsAndSafety,
            .dataOwnership
        ]))
        XCTAssertEqual(
            steps.filter { $0.presents == .newClient }.map(\.anchor),
            [.ncOwner, .ncPets, .ncSave],
            "The create-client lesson should open one coherent New Client mini-flow."
        )
        XCTAssertTrue(
            steps.filter { $0.presents == .newClient }.allSatisfy(\.allowsTargetInteraction),
            "The New Client lesson must let the user type into the form and tap Create instead of the overlay swallowing the action."
        )
        let saveStep = try XCTUnwrap(steps.first { $0.anchor == .ncSave })
        XCTAssertTrue(saveStep.purpose.localizedCaseInsensitiveContains("Create"))
        XCTAssertFalse(saveStep.purpose.localizedCaseInsensitiveContains("without saving"))
        XCTAssertGreaterThanOrEqual(steps.compactMap(\.coachTip).count, 8)
        XCTAssertTrue(steps.contains { $0.purpose.localizedCaseInsensitiveContains("check in") })
        XCTAssertTrue(steps.contains { $0.purpose.localizedCaseInsensitiveContains("checkout") })
        XCTAssertTrue(steps.contains { $0.purpose.localizedCaseInsensitiveContains("receipt") })
        XCTAssertTrue(steps.contains { $0.purpose.localizedCaseInsensitiveContains("history") })
        XCTAssertTrue(steps.contains { $0.purpose.localizedCaseInsensitiveContains("iCloud") })
        XCTAssertTrue(steps.contains { $0.purpose.localizedCaseInsensitiveContains("Start Fresh") })
        XCTAssertFalse(steps.contains { $0.title.trimmed.isEmpty || $0.directive.trimmed.isEmpty || $0.purpose.trimmed.isEmpty })
    }

    func testFullWalkthroughIncludesClientDetailsAndEndsAtStartFresh() throws {
        let steps = WalkthroughController.fullTour()

        XCTAssertTrue(
            steps.contains { $0.title.localizedCaseInsensitiveContains("Client Details") },
            "The walkthrough should open and explain an actual client profile."
        )
        XCTAssertTrue(
            steps.contains { $0.title.localizedCaseInsensitiveContains("Emergency Contacts") },
            "Client Details should teach emergency contacts because they are not obvious from the Clients list."
        )
        XCTAssertTrue(
            steps.contains {
                $0.title.localizedCaseInsensitiveContains("Pet Actions")
                    && $0.purpose.localizedCaseInsensitiveContains("next stops")
            },
            "Client Details should introduce the pet action row before the dedicated check-in, checkout, and history stops."
        )

        let finalStep = try XCTUnwrap(steps.last)
        XCTAssertTrue(finalStep.title.localizedCaseInsensitiveContains("Wipe"))
        XCTAssertTrue(finalStep.purpose.localizedCaseInsensitiveContains("empty workspace"))
        XCTAssertTrue(finalStep.purpose.localizedCaseInsensitiveContains("real business"))
    }

    func testFullWalkthroughTeachesCheckoutAndHistoryAsDedicatedProcess() throws {
        let steps = WalkthroughController.fullTour()
        let anchors = steps.map(\.anchor)

        XCTAssertTrue(anchors.contains(.cdCheckIn), "Check In should have its own stop, not only a grouped pet-actions explanation.")
        XCTAssertTrue(anchors.contains(.cdCheckOut), "Check Out should have its own stop so the user understands when checkout becomes available.")
        XCTAssertTrue(anchors.contains(.coServices), "The tour should open checkout and explain the Services step in the real checkout UI.")
        XCTAssertTrue(anchors.contains(.coDetails), "The tour should open checkout and explain the Notes & Photos step in the real checkout UI.")
        XCTAssertTrue(anchors.contains(.coPayment), "The tour should open checkout and explain the Payment step in the real checkout UI.")
        XCTAssertTrue(anchors.contains(.coReview), "The tour should open checkout and explain the Review step in the real checkout UI.")
        XCTAssertTrue(anchors.contains(.coConfirm), "The tour should explain the final Confirm & Pay action in the real checkout UI.")
        XCTAssertTrue(anchors.contains(.cdPetHistory), "Pet History should have its own stop because it opens a deeper history view.")
        XCTAssertTrue(anchors.contains(.cdHistory), "Recent History should remain part of the client-detail chapter.")

        let checkInStep = try XCTUnwrap(steps.first { $0.anchor == .cdCheckIn })
        XCTAssertTrue(checkInStep.allowsTargetInteraction)
        XCTAssertTrue(checkInStep.requiresTargetAction)

        let checkOutStep = try XCTUnwrap(steps.first { $0.anchor == .cdCheckOut })
        XCTAssertTrue(checkOutStep.allowsTargetInteraction)
        XCTAssertTrue(checkOutStep.requiresTargetAction)
        XCTAssertTrue(checkOutStep.purpose.localizedCaseInsensitiveContains("services"))
        XCTAssertTrue(checkOutStep.purpose.localizedCaseInsensitiveContains("payment"))

        let checkoutSteps = steps.filter { $0.presents == .checkout }
        XCTAssertEqual(checkoutSteps.map(\.anchor), [.coServices, .coDetails, .coPayment, .coReview, .coConfirm])
        XCTAssertTrue(checkoutSteps.allSatisfy { $0.lesson == .checkoutAndMoney })
        XCTAssertTrue(checkoutSteps[0].purpose.localizedCaseInsensitiveContains("subtotal"))
        XCTAssertTrue(checkoutSteps[1].purpose.localizedCaseInsensitiveContains("notes"))
        XCTAssertTrue(checkoutSteps[1].purpose.localizedCaseInsensitiveContains("photos"))
        XCTAssertTrue(checkoutSteps[2].purpose.localizedCaseInsensitiveContains("tip"))
        XCTAssertTrue(checkoutSteps[2].purpose.localizedCaseInsensitiveContains("reference"))
        XCTAssertTrue(checkoutSteps[3].purpose.localizedCaseInsensitiveContains("history"))
        XCTAssertTrue(checkoutSteps[4].purpose.localizedCaseInsensitiveContains("insights"))

        let petHistoryStep = try XCTUnwrap(steps.first { $0.anchor == .cdPetHistory })
        XCTAssertTrue(petHistoryStep.purpose.localizedCaseInsensitiveContains("search"))
        XCTAssertTrue(petHistoryStep.purpose.localizedCaseInsensitiveContains("export"))
    }

    func testSpanishWalkthroughCopyDoesNotLeaveWalkthroughInEnglish() {
        UserDefaults.standard.set(AppLanguageOverride.es.rawValue, forKey: AppSettingsKeys.appLanguageOverride)

        let leakedCopy = WalkthroughController.fullTour().flatMap { step in
            [step.title, step.directive, step.purpose, step.coachTip].compactMap(\.self)
        }.filter { $0.localizedCaseInsensitiveContains("walkthrough") }

        XCTAssertTrue(leakedCopy.isEmpty, "Spanish walkthrough copy should use recorrido instead of leaving walkthrough in English: \(leakedCopy)")
    }

    func testFullWalkthroughCopyStaysShortAndPlainInEnglish() {
        UserDefaults.standard.set(AppLanguageOverride.en.rawValue, forKey: AppSettingsKeys.appLanguageOverride)

        assertWalkthroughCopyIsShortAndPlain(WalkthroughController.fullTour())
    }

    func testFullWalkthroughCopyStaysShortAndPlainInSpanish() {
        UserDefaults.standard.set(AppLanguageOverride.es.rawValue, forKey: AppSettingsKeys.appLanguageOverride)

        assertWalkthroughCopyIsShortAndPlain(WalkthroughController.fullTour())
    }

    func testAddPetWalkthroughWaitsForLiveTargetInsteadOfMacToolbarFallback() {
        XCTAssertEqual(
            WalkthroughController.addPetSpotlightFallback,
            .none,
            "Add Pet should highlight the visible paw Add Pet control; a top-trailing fallback can point at empty toolbar space on macOS."
        )
    }

    func testWalkthroughReplayRestartsFromFirstStepEvenWhenAlreadyActive() throws {
        let controller = WalkthroughController()
        let steps = WalkthroughController.fullTour()
        controller.start(steps)
        controller.advance()
        controller.advance()

        XCTAssertGreaterThan(controller.currentIndex, 0)

        controller.restart(WalkthroughController.fullTour())

        XCTAssertTrue(controller.isActive)
        XCTAssertEqual(controller.currentIndex, 0)
        XCTAssertEqual(controller.currentStep?.anchor, .dashboard)
    }

    func testWalkthroughBackReturnsToPreviousClientDetailActionStep() throws {
        let controller = WalkthroughController()
        let steps = WalkthroughController.fullTour()
        let checkOutIndex = try XCTUnwrap(steps.firstIndex { $0.anchor == .cdCheckOut })
        controller.start(steps)

        while controller.currentIndex < checkOutIndex {
            controller.advance()
        }

        XCTAssertEqual(controller.currentStep?.anchor, .cdCheckOut)
        XCTAssertTrue(controller.canGoBack)

        controller.goBack()

        XCTAssertEqual(controller.currentStep?.anchor, .cdCheckIn)
        XCTAssertTrue(controller.isActive)
    }

    func testWalkthroughCompletesNewClientChapterAfterUserCreatesClient() throws {
        let controller = WalkthroughController()
        let steps = WalkthroughController.fullTour()
        let newClientIndex = try XCTUnwrap(steps.firstIndex { $0.presents == .newClient })
        controller.start(steps)

        while controller.currentIndex < newClientIndex {
            controller.advance()
        }

        XCTAssertEqual(controller.currentStep?.anchor, .ncOwner)
        XCTAssertEqual(controller.currentStep?.presents, .newClient)

        controller.completePresentation(.newClient)

        XCTAssertTrue(controller.isActive)
        XCTAssertNil(controller.currentStep?.presents)
        XCTAssertEqual(controller.currentStep?.anchor, .cdOwner)
        XCTAssertEqual(controller.currentStep?.route, .demoClientDetail)
    }

    func testWalkthroughCompletionKeepsCreatedClientPreferenceForDetailsChapter() throws {
        let controller = WalkthroughController()
        let client = Client(firstName: "Tour", lastName: "Client")
        context.insert(client)
        try context.save()

        let steps = WalkthroughController.fullTour()
        let newClientIndex = try XCTUnwrap(steps.firstIndex { $0.presents == .newClient })
        controller.start(steps)

        while controller.currentIndex < newClientIndex {
            controller.advance()
        }

        controller.focusClientDetail(client.persistentModelID)
        controller.completePresentation(.newClient)

        XCTAssertEqual(controller.currentStep?.anchor, .cdOwner)
        XCTAssertEqual(controller.preferredClientDetailID, client.persistentModelID)
    }

    func testUITestWalkthroughLaunchFlagIsNarrowAndExplicit() {
        unsetenv("PAWTRACKR_UI_TESTING")
        unsetenv("PAWTRACKR_UI_START_WALKTHROUGH")
        XCTAssertFalse(AppRuntime.shouldStartWalkthroughForUITesting)

        setenv("PAWTRACKR_UI_TESTING", "1", 1)
        setenv("PAWTRACKR_UI_START_WALKTHROUGH", "0", 1)
        XCTAssertFalse(AppRuntime.shouldStartWalkthroughForUITesting)

        setenv("PAWTRACKR_UI_START_WALKTHROUGH", "1", 1)
        XCTAssertTrue(AppRuntime.shouldStartWalkthroughForUITesting)

        unsetenv("PAWTRACKR_UI_TESTING")
        setenv("PAWTRACKR_UI_START_WALKTHROUGH", "1", 1)
        XCTAssertFalse(AppRuntime.shouldStartWalkthroughForUITesting)
    }


    func testWalkthroughTargetFrameRejectsOffscreenAndTinyRects() {
        let container = CGSize(width: 1024, height: 768)
        let insets = EdgeInsets(top: 24, leading: 0, bottom: 20, trailing: 0)

        XCTAssertNil(WalkthroughTargetFrame.validated(CGRect(x: -800, y: -200, width: 40, height: 40), in: container, safeAreaInsets: insets))
        XCTAssertNil(WalkthroughTargetFrame.validated(CGRect(x: 200, y: 200, width: 0.5, height: 24), in: container, safeAreaInsets: insets))

        // Also reject non-finite values
        XCTAssertNil(WalkthroughTargetFrame.validated(CGRect(x: CGFloat.nan, y: 0, width: 40, height: 40), in: container, safeAreaInsets: insets))
        XCTAssertNil(WalkthroughTargetFrame.validated(CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 40), in: container, safeAreaInsets: insets))

        // WalkthroughTargetFrame.validated should clamp rects to safe bounds with an 8pt buffer:
        // maxX: 1024 - 8 = 1016
        // maxY: (768 - 20 bottom inset) - 8 = 740
        let visible = WalkthroughTargetFrame.validated(CGRect(x: 980, y: 720, width: 80, height: 80), in: container, safeAreaInsets: insets)
        XCTAssertEqual(visible?.maxX, 1016)
        XCTAssertEqual(visible?.maxY, 740)
    }

    func testWalkthroughInteractiveTargetBubbleDoesNotOverlapIPadCheckoutTarget() {
        let step = WalkthroughStep(
            id: 0,
            anchor: .cdCheckOut,
            title: "Check Out",
            directive: "Tap the highlighted button.",
            purpose: "Finish the visit.",
            allowsTargetInteraction: true,
            requiresTargetAction: true
        )
        let container = CGSize(width: 834, height: 1_194)
        let target = CGRect(x: 328, y: 424, width: 252, height: 78)

        let result = WalkthroughOverlayLayout.layout(
            step: step,
            targetRect: target,
            containerSize: container,
            safeAreaInsets: EdgeInsets(top: 24, leading: 0, bottom: 20, trailing: 0)
        )

        let spotlight = try! XCTUnwrap(result.spotlight)
        XCTAssertNotEqual(result.placement, .center)
        XCTAssertFalse(result.bubbleFrame.intersects(spotlight), "Interactive checkout bubble must not cover the tappable target.")
        XCTAssertTrue(CGRect(origin: .zero, size: container).contains(result.bubbleFrame))
    }

    func testWalkthroughLayoutShrinksInsteadOfClampingBubbleOverTarget() {
        let step = WalkthroughStep(
            id: 0,
            anchor: .cdCheckOut,
            title: "Check Out",
            directive: "Tap the highlighted button.",
            purpose: "Finish the visit.",
            allowsTargetInteraction: true,
            requiresTargetAction: true
        )
        let container = CGSize(width: 834, height: 600)
        let target = CGRect(x: 260, y: 200, width: 300, height: 260)

        let result = WalkthroughOverlayLayout.layout(
            step: step,
            targetRect: target,
            containerSize: container,
            safeAreaInsets: EdgeInsets(top: 24, leading: 0, bottom: 20, trailing: 0)
        )

        let spotlight = try! XCTUnwrap(result.spotlight)
        XCTAssertNotEqual(result.placement, .center)
        XCTAssertFalse(result.bubbleFrame.intersects(spotlight), "Clamping a bubble into safe bounds must not push it back over an interactive target.")
        XCTAssertTrue(CGRect(origin: .zero, size: container).contains(result.bubbleFrame))
    }

    func testWalkthroughRightSideCheckoutTargetUsesLeadingBubbleOnIPadLandscape() {
        let step = WalkthroughStep(
            id: 0,
            anchor: .cdCheckOut,
            title: "Check Out",
            directive: "Tap the highlighted button.",
            purpose: "Finish the visit.",
            allowsTargetInteraction: true,
            requiresTargetAction: true
        )
        let container = CGSize(width: 1_194, height: 834)
        let target = CGRect(x: 670, y: 406, width: 252, height: 88)

        let result = WalkthroughOverlayLayout.layout(
            step: step,
            targetRect: target,
            containerSize: container,
            safeAreaInsets: EdgeInsets(top: 24, leading: 0, bottom: 20, trailing: 0)
        )

        let spotlight = try! XCTUnwrap(result.spotlight)
        XCTAssertEqual(result.placement, .leading)
        XCTAssertFalse(result.bubbleFrame.intersects(spotlight), "Right-side iPad actions need a leading bubble so the highlighted button remains tappable.")
        XCTAssertTrue(CGRect(origin: .zero, size: container).contains(result.bubbleFrame))
    }

    func testWalkthroughRightSideCheckoutTargetUsesLeadingBubbleInShortDetailHost() {
        let step = WalkthroughStep(
            id: 0,
            anchor: .cdCheckOut,
            title: "Check Out",
            directive: "Tap the highlighted button.",
            purpose: "Finish the visit.",
            allowsTargetInteraction: true,
            requiresTargetAction: true
        )
        let container = CGSize(width: 834, height: 600)
        let target = CGRect(x: 430, y: 396, width: 252, height: 88)

        let result = WalkthroughOverlayLayout.layout(
            step: step,
            targetRect: target,
            containerSize: container,
            safeAreaInsets: EdgeInsets(top: 24, leading: 0, bottom: 20, trailing: 0)
        )

        let spotlight = try! XCTUnwrap(result.spotlight)
        XCTAssertEqual(result.placement, .leading)
        XCTAssertFalse(result.bubbleFrame.intersects(spotlight), "A short iPad detail host should still place the bubble beside a right-side action instead of clamping it over the target.")
        XCTAssertTrue(CGRect(origin: .zero, size: container).contains(result.bubbleFrame))
    }

    func testWalkthroughBubbleStaysInBoundsForIPadLandscapePetHistoryTarget() {
        let step = WalkthroughStep(
            id: 0,
            anchor: .cdPetHistory,
            title: "Pet History",
            directive: "Open the pet timeline.",
            purpose: "Review past visits."
        )
        let container = CGSize(width: 1_194, height: 834)
        let target = CGRect(x: 834, y: 356, width: 270, height: 76)

        let result = WalkthroughOverlayLayout.layout(
            step: step,
            targetRect: target,
            containerSize: container,
            safeAreaInsets: EdgeInsets(top: 24, leading: 0, bottom: 20, trailing: 0)
        )

        let spotlight = try! XCTUnwrap(result.spotlight)
        XCTAssertNotEqual(result.placement, .center)
        XCTAssertFalse(result.bubbleFrame.intersects(spotlight))
        XCTAssertTrue(CGRect(origin: .zero, size: container).contains(result.bubbleFrame))
    }

    func testWalkthroughCompactTabBarBubbleAppearsAboveTarget() {
        let step = WalkthroughStep(
            id: 0,
            anchor: .dashboard,
            title: "Dashboard",
            directive: "Start here.",
            purpose: "Daily overview."
        )
        let container = CGSize(width: 393, height: 852)
        let tabTarget = CGRect(x: 20, y: 766, width: 58, height: 44)

        let result = WalkthroughOverlayLayout.layout(
            step: step,
            targetRect: tabTarget,
            containerSize: container,
            safeAreaInsets: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)
        )

        let spotlight = try! XCTUnwrap(result.spotlight)
        XCTAssertEqual(result.placement, .above)
        XCTAssertLessThanOrEqual(result.bubbleFrame.maxY, spotlight.minY)
        XCTAssertTrue(CGRect(origin: .zero, size: container).contains(result.bubbleFrame))
    }

    func testWalkthroughMacSettingsBubbleIsInBoundsAndOffTarget() {
        let step = WalkthroughStep(
            id: 0,
            anchor: .setBusiness,
            title: "Business Settings",
            directive: "Check your shop profile.",
            purpose: "These fields power receipts."
        )
        let container = CGSize(width: 1_024, height: 768)
        let target = CGRect(x: 44, y: 172, width: 560, height: 150)

        let result = WalkthroughOverlayLayout.layout(
            step: step,
            targetRect: target,
            containerSize: container,
            safeAreaInsets: EdgeInsets(top: 24, leading: 0, bottom: 0, trailing: 0)
        )

        let spotlight = try! XCTUnwrap(result.spotlight)
        XCTAssertNotEqual(result.placement, .center)
        XCTAssertFalse(result.bubbleFrame.intersects(spotlight))
        XCTAssertTrue(CGRect(origin: .zero, size: container).contains(result.bubbleFrame))
    }

    func testWalkthroughRemembersCreatedClientForDetailsChapter() throws {
        let controller = WalkthroughController()
        let client = Client(firstName: "Tour", lastName: "Client")
        context.insert(client)
        try context.save()

        controller.focusClientDetail(client.persistentModelID)

        XCTAssertEqual(controller.preferredClientDetailID, client.persistentModelID)

        controller.restart(WalkthroughController.fullTour())

        XCTAssertNil(controller.preferredClientDetailID)
    }

    func testFinish_RejectsBlankBusinessName() async {
        let settings = AppSettings()
        let viewModel = OnboardingViewModel(modelContext: context, appSettings: settings)
        viewModel.name = "   "
        viewModel.pin = "1234"
        viewModel.confirmPin = "1234"

        var completionFired = false
        await viewModel.finish(seedSampleData: false) { completionFired = true }

        XCTAssertFalse(completionFired)
        XCTAssertNotNil(viewModel.saveError)
    }

    func testFinish_RejectsMismatchedPINs() async {
        let settings = AppSettings()
        let viewModel = OnboardingViewModel(modelContext: context, appSettings: settings)
        viewModel.name = "Test"
        viewModel.pin = "1111"
        viewModel.confirmPin = "2222"

        var completionFired = false
        await viewModel.finish(seedSampleData: false) { completionFired = true }

        XCTAssertFalse(completionFired)
        XCTAssertNotNil(viewModel.saveError)
    }

    func testFinish_GuardsAgainstDoubleInvocation() async {
        let settings = AppSettings()
        let viewModel = OnboardingViewModel(modelContext: context, appSettings: settings)
        viewModel.name = "Test"
        viewModel.pin = "1234"
        viewModel.confirmPin = "1234"

        // Two concurrent finishes — the second should be a no-op while the first
        // is still in flight.
        async let first = viewModel.finish(seedSampleData: false) { }
        async let second = viewModel.finish(seedSampleData: false) { }
        _ = await (first, second)

        let configs = try? context.fetch(FetchDescriptor<BusinessConfig>())
        XCTAssertEqual(configs?.count, 1, "Should never create more than one BusinessConfig.")
    }

    private func resetAppSettingsDefaults() {
        let defaults = UserDefaults.standard
        [
            AppSettingsKeys.isLockEnabled,
            AppSettingsKeys.isBiometricLockEnabled,
            AppSettingsKeys.legacyAppPIN,
            AppSettingsKeys.lastPINChangeDate,
            AppSettingsKeys.autoLockOnBackground,
            AppSettingsKeys.autoLockAfterInactivity,
            AppSettingsKeys.businessName,
            AppSettingsKeys.currencySymbol,
            AppSettingsKeys.hasConfiguredPrices,
            AppSettingsKeys.hasAddedFirstClient,
            AppSettingsKeys.hasCompletedFirstVisit,
            AppSettingsKeys.isChecklistDismissed,
            AppSettingsKeys.hasSeenAppTour,
            AppSettingsKeys.appLanguageOverride
        ].forEach { key in
            defaults.removeObject(forKey: key)
        }
        // PIN now lives in the Keychain; clear it explicitly so tests start fresh.
        KeychainStorage.remove(forKey: AppSettingsKeys.appPINKeychainAccount)
    }

    private func assertWalkthroughCopyIsShortAndPlain(_ steps: [WalkthroughStep], file: StaticString = #filePath, line: UInt = #line) {
        for step in steps {
            XCTAssertLessThanOrEqual(step.directive.count, 86, "Directive is too long for \(step.anchor): \(step.directive)", file: file, line: line)
            XCTAssertLessThanOrEqual(step.purpose.count, 190, "Purpose is too long for \(step.anchor): \(step.purpose)", file: file, line: line)
            if let coachTip = step.coachTip {
                XCTAssertLessThanOrEqual(coachTip.count, 150, "Coach tip is too long for \(step.anchor): \(coachTip)", file: file, line: line)
            }

            for text in [step.directive, step.purpose] + [step.coachTip].compactMap(\.self) {
                XCTAssertFalse(text.contains(";"), "Use short sentences instead of semicolons for \(step.anchor): \(text)", file: file, line: line)
                XCTAssertFalse(text.contains(" — "), "Use short sentences instead of long dash clauses for \(step.anchor): \(text)", file: file, line: line)
            }
        }
    }
}
