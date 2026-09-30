import XCTest
import SwiftData
@testable import Pawtrackr

/// Onboarding adds sample clients only when the user asks and the salon is
/// provably empty, and it keeps the PIN out of the saved draft.
@MainActor
final class OnboardingSampleDataTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private let draftKey = "com.pawtrackr.onboarding.draft"

    override func setUpWithError() throws {
        try super.setUpWithError()
        resetSettings()
        let schema = Schema(PawtrackrSchema.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [config])
        context = container.mainContext
    }

    override func tearDownWithError() throws {
        container = nil
        context = nil
        resetSettings()
        try super.tearDownWithError()
    }

    // MARK: - The choice

    func testChoosingSamplesInAnEmptySalonSeedsThemBeforeTheTourIsArmed() async throws {
        let settings = AppSettings()
        settings.hasSeenAppTour = true
        let viewModel = makeViewModel(settings: settings)

        var sampleClientsAtCompletion = -1
        var tourArmedAtCompletion = false
        let task = await viewModel.finish(seedSampleData: true) { [container] in
            sampleClientsAtCompletion = (try? SampleData.sampleClientCount(in: ModelContext(container!))) ?? -1
            tourArmedAtCompletion = !settings.hasSeenAppTour
        }
        _ = await task?.result

        XCTAssertEqual(viewModel.lastSampleDataDecision, .seed)
        XCTAssertEqual(sampleClientsAtCompletion, 2,
                       "The samples are saved before the tour is armed, so the tour can see them.")
        XCTAssertTrue(tourArmedAtCompletion)
    }

    func testStartingWithTheRealBusinessAddsNoClients() async throws {
        let settings = AppSettings()
        let viewModel = makeViewModel(settings: settings)

        let task = await viewModel.finish(seedSampleData: false) { }
        _ = await task?.result

        XCTAssertEqual(viewModel.lastSampleDataDecision, .skip(.notChosen))
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<Client>()), 0)
        XCTAssertGreaterThan(try ModelContext(container).fetchCount(FetchDescriptor<Service>()), 0,
                             "The starter service menu is still added.")
        XCTAssertFalse(settings.hasSeenAppTour, "The tour still runs.")
    }

    func testSamplesAreNotAddedWhenABusinessProfileAlreadyExists() async throws {
        // An existing local salon profile that is not yet marked set up.
        context.insert(BusinessConfig(name: "Harbor Grooming"))
        try context.save()

        try await assertFinishAddsNoSamples(expecting: .skip(.salonHasData))
    }

    func testSamplesAreNotAddedWhenClientsAlreadyExist() async throws {
        context.insert(Client(firstName: "Rosa", lastName: "Diaz"))
        try context.save()

        try await assertFinishAddsNoSamples(expecting: .skip(.salonHasData), expectedClients: 1)
    }

    func testSamplesAreNotAddedWhenABackupHoldsTheUsersClients() async throws {
        try await assertFinishAddsNoSamples(expecting: .skip(.backupFound), restorableClients: 4)
    }

    func testFinishStepExplainsWhySamplesAreUnavailable() throws {
        let viewModel = makeViewModel(settings: AppSettings())
        XCTAssertEqual(viewModel.sampleDataAvailability, .seed)

        viewModel.restorableClientCount = 2
        XCTAssertEqual(viewModel.sampleDataAvailability, .skip(.backupFound))
    }

    // MARK: - PIN stays out of the draft

    func testTheDraftNeverHoldsThePIN() {
        UserDefaults.standard.removeObject(forKey: draftKey)
        let viewModel = OnboardingViewModel(modelContext: context, appSettings: AppSettings())

        viewModel.name = "Bark & Bathe"
        viewModel.pin = "4826"
        viewModel.confirmPin = "4826"
        viewModel.biometricsEnabled = true

        let draft = UserDefaults.standard.dictionary(forKey: draftKey)
        XCTAssertEqual(draft?["name"] as? String, "Bark & Bathe", "The rest of the draft still saves.")
        XCTAssertNil(draft?["pin"])
        XCTAssertNil(draft?["confirmPin"])
        XCTAssertFalse(String(describing: draft ?? [:]).contains("4826"))
    }

    func testBindingRemovesAPINAnOlderBuildSavedInTheDraft() {
        UserDefaults.standard.set(["name": "Bark & Bathe", "pin": "4826", "confirmPin": "4826"], forKey: draftKey)

        let viewModel = OnboardingViewModel(modelContext: context, appSettings: nil)
        XCTAssertEqual(viewModel.pin, "", "A PIN from an old draft isn't restored.")
        XCTAssertEqual(viewModel.name, "Bark & Bathe")
        XCTAssertEqual(UserDefaults.standard.dictionary(forKey: draftKey)?["pin"] as? String, "4826",
                       "init never writes defaults; the cleanup happens when the view binds.")

        viewModel.bindIfNeeded(modelContext: context, appSettings: AppSettings())

        let draft = UserDefaults.standard.dictionary(forKey: draftKey)
        XCTAssertNil(draft?["pin"])
        XCTAssertNil(draft?["confirmPin"])
        XCTAssertEqual(draft?["name"] as? String, "Bark & Bathe")
    }

    // MARK: - Helpers

    private func assertFinishAddsNoSamples(
        expecting decision: SampleDataSeedPolicy.Decision,
        restorableClients: Int = 0,
        expectedClients: Int = 0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let settings = AppSettings()
        let viewModel = makeViewModel(settings: settings)
        viewModel.restorableClientCount = restorableClients

        let task = await viewModel.finish(seedSampleData: true) { }
        _ = await task?.result

        XCTAssertNil(viewModel.saveError, file: file, line: line)
        XCTAssertEqual(viewModel.lastSampleDataDecision, decision, file: file, line: line)
        let fresh = ModelContext(container)
        XCTAssertEqual(try SampleData.sampleClientCount(in: fresh), 0, file: file, line: line)
        XCTAssertEqual(try fresh.fetchCount(FetchDescriptor<Client>()), expectedClients, file: file, line: line)
        XCTAssertEqual(try fresh.fetchCount(FetchDescriptor<Visit>()), 0, file: file, line: line)
        XCTAssertTrue(
            try fresh.fetch(FetchDescriptor<Service>()).allSatisfy { $0.basePrice == nil },
            "No sample clients, so no example prices either.",
            file: file, line: line
        )
    }

    private func makeViewModel(settings: AppSettings) -> OnboardingViewModel {
        let viewModel = OnboardingViewModel(modelContext: context, appSettings: settings)
        viewModel.name = "Harbor Grooming"
        viewModel.pinSkipped = true
        return viewModel
    }

    private func resetSettings() {
        let defaults = UserDefaults.standard
        [
            AppSettingsKeys.isLockEnabled,
            AppSettingsKeys.isBiometricLockEnabled,
            AppSettingsKeys.businessName,
            AppSettingsKeys.currencySymbol,
            AppSettingsKeys.isChecklistDismissed,
            AppSettingsKeys.hasSeenAppTour,
            AppSettingsKeys.onboardingRole
        ].forEach { defaults.removeObject(forKey: $0) }
        defaults.removeObject(forKey: draftKey)
        defaults.removeObject(forKey: SamplePriceRecord.userDefaultsKey)
    }
}
