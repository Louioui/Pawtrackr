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
        XCTAssertEqual(viewModel.regionalValidationMessage, "Enter a valid email address or leave it blank for now.")

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
        await viewModel.finish(seedSampleData: false) {
            completed = true
        }

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

        await viewModel.finish(seedSampleData: true) { }

        XCTAssertNil(viewModel.saveError)
        XCTAssertTrue(settings.hasConfiguredPrices)
        XCTAssertTrue(settings.hasAddedFirstClient)
        XCTAssertTrue(settings.hasCompletedFirstVisit)
        XCTAssertGreaterThan(try context.fetchCount(FetchDescriptor<Client>()), 0)
        XCTAssertGreaterThan(try context.fetchCount(FetchDescriptor<Visit>()), 0)
        XCTAssertGreaterThan(try context.fetchCount(FetchDescriptor<Service>()), 0)
    }

    private func resetAppSettingsDefaults() {
        let defaults = UserDefaults.standard
        [
            AppSettingsKeys.isLockEnabled,
            AppSettingsKeys.isBiometricLockEnabled,
            AppSettingsKeys.appPIN,
            AppSettingsKeys.lastPINChangeDate,
            AppSettingsKeys.autoLockOnBackground,
            AppSettingsKeys.autoLockAfterInactivity,
            AppSettingsKeys.businessName,
            AppSettingsKeys.currencySymbol,
            AppSettingsKeys.hasConfiguredPrices,
            AppSettingsKeys.hasAddedFirstClient,
            AppSettingsKeys.hasCompletedFirstVisit,
            AppSettingsKeys.isChecklistDismissed
        ].forEach { key in
            defaults.removeObject(forKey: key)
        }
    }
}
