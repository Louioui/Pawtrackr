import XCTest
import SwiftData
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
            AppSettingsKeys.hasSeenAppTour
        ].forEach { key in
            defaults.removeObject(forKey: key)
        }
        // PIN now lives in the Keychain; clear it explicitly so tests start fresh.
        KeychainStorage.remove(forKey: AppSettingsKeys.appPINKeychainAccount)
    }
}
