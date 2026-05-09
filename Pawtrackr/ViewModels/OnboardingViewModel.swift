import Foundation
import Observation
import SwiftData
import OSLog
import SwiftUI

@Observable
final class OnboardingViewModel {
    private var modelContext: ModelContext?
    private var appSettings: AppSettings?

    enum Step: Int, CaseIterable {
        case welcome, businessProfile, regional, security, permissions, warmStart
        
        var title: String {
            switch self {
            case .welcome: return "Welcome"
            case .businessProfile: return "Business Profile"
            case .regional: return "Regional Info"
            case .security: return "Security"
            case .permissions: return "Permissions"
            case .warmStart: return "Finish"
            }
        }
    }

    var currentStep: Step = .welcome
    var name: String = ""
    var email: String = ""
    var phone: String = ""
    var address: String = ""
    var logoData: Data? = nil
    var pin: String = ""
    var confirmPin: String = ""
    var biometricsEnabled: Bool = false
    var lockOnBackgroundEnabled: Bool = true
    var autoLockAfterInactivityEnabled: Bool = false
    var currentCurrency: String = "$"
    var isSaving: Bool = false
    var saveError: String? = nil
    
    var currencySymbol: String {
        get { currentCurrency }
        set { currentCurrency = newValue }
    }

    private let logger = Logger(subsystem: "com.pawtrackr", category: "Onboarding")
    private let biometrics = BiometricAuthenticator()
    private var hasLoadedInitialState = false
    
    // MARK: - Init
    init(modelContext: ModelContext?, appSettings: AppSettings?) {
        self.modelContext = modelContext
        self.appSettings = appSettings
        self.currentCurrency = appSettings?.currencySymbol ?? "$"
        self.lockOnBackgroundEnabled = appSettings?.autoLockOnBackground ?? true
        self.autoLockAfterInactivityEnabled = appSettings?.autoLockAfterInactivity ?? false
        self.biometricsEnabled = (appSettings?.isBiometricLockEnabled ?? false) && isBiometricsAvailable
    }

    func bindIfNeeded(modelContext: ModelContext, appSettings: AppSettings) {
        self.modelContext = modelContext
        self.appSettings = appSettings

        guard !hasLoadedInitialState else { return }
        hasLoadedInitialState = true

        currentCurrency = appSettings.currencySymbol
        lockOnBackgroundEnabled = appSettings.autoLockOnBackground
        autoLockAfterInactivityEnabled = appSettings.autoLockAfterInactivity
        biometricsEnabled = appSettings.isBiometricLockEnabled && isBiometricsAvailable

        do {
            var descriptor = FetchDescriptor<BusinessConfig>()
            descriptor.fetchLimit = 1
            if let config = try modelContext.fetch(descriptor).first {
                if !config.name.trimmed.isEmpty {
                    name = config.name
                }
                email = config.email ?? ""
                phone = config.phone ?? ""
                address = config.address ?? ""
                logoData = config.logoData
            }
        } catch {
            logger.error("Failed to hydrate onboarding state: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    // MARK: - Navigation
    func nextStep() {
        guard canGoNext else {
            HapticManager.notify(.error)
            return
        }
        
        TelemetryService.shared.track(event: "onboarding_step_completed", parameters: ["step": currentStep.title])
        
        guard let next = Step(rawValue: currentStep.rawValue + 1) else { return }
        HapticManager.impact(.medium)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            currentStep = next
        }
    }
    
    func previousStep() {
        guard let prev = Step(rawValue: currentStep.rawValue - 1) else { return }
        HapticManager.impact(.light)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            currentStep = prev
        }
    }
    
    func goToStep(_ step: Step) {
        guard step.rawValue < currentStep.rawValue else { return }
        HapticManager.impact(.light)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            currentStep = step
        }
    }
    
    var canGoNext: Bool {
        switch currentStep {
        case .welcome:
            return true
        case .businessProfile:
            return businessNameValidationMessage == nil
        case .regional:
            return regionalValidationMessage == nil
        case .security:
            let normalizedPIN = pin.filter(\.isNumber)
            let normalizedConfirm = confirmPin.filter(\.isNumber)
            return AppSettings.isValidPIN(normalizedPIN) && normalizedPIN == normalizedConfirm
        case .permissions:
            return true
        case .warmStart:
            return true
        }
    }

    var primaryActionTitle: String {
        switch currentStep {
        case .welcome:
            return "Get Started"
        case .permissions:
            return "Review Setup"
        default:
            return "Continue"
        }
    }

    var currentValidationMessage: String? {
        switch currentStep {
        case .businessProfile:
            return businessNameValidationMessage
        case .regional:
            return regionalValidationMessage
        case .security:
            return securityValidationMessage
        default:
            return nil
        }
    }

    var businessNameValidationMessage: String? {
        name.trimmed.isEmpty ? "Add your business name to continue." : nil
    }

    var regionalValidationMessage: String? {
        let trimmedEmail = email.trimmed
        guard !trimmedEmail.isEmpty else { return nil }
        // Use a more inclusive but standard regex
        let emailRegEx = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPred = NSPredicate(format:"SELF MATCHES %@", emailRegEx)
        return emailPred.evaluate(with: trimmedEmail) ? nil : "Enter a valid email address (e.g., hello@business.com)."
    }

    var securityValidationMessage: String? {
        let normalizedPIN = pin.filter(\.isNumber)
        let normalizedConfirm = confirmPin.filter(\.isNumber)

        if (!pin.isEmpty && normalizedPIN != pin) || (!confirmPin.isEmpty && normalizedConfirm != confirmPin) {
            return "PIN must use numbers only."
        }
        if !pin.isEmpty && normalizedPIN.count < 4 {
            return "PIN must be 4 digits."
        }
        if !confirmPin.isEmpty && normalizedConfirm.count < 4 {
            return "Confirm your 4-digit PIN."
        }
        if normalizedPIN.count == 4 && normalizedConfirm.count == 4 && normalizedPIN != normalizedConfirm {
            return "PINs do not match."
        }
        return nil
    }

    var isBiometricsAvailable: Bool {
        biometrics.biometricType() != .none
    }

    var biometricTitle: String {
        switch biometrics.biometricType() {
        case .faceID:
            return "Face ID Unlock"
        case .touchID:
            return "Touch ID Unlock"
        case .none:
            return "Biometric Unlock"
        }
    }

    var biometricSubtitle: String {
        isBiometricsAvailable
            ? "Use biometrics alongside your PIN for faster unlock."
            : "This device does not have biometric unlock available right now."
    }
    
    // MARK: - Actions

    @MainActor
    func finish(seedSampleData: Bool, onComplete: @escaping () -> Void) async {
        guard !isSaving else { return }
        isSaving = true
        saveError = nil
        await Task.yield()
        
        logger.info("Starting onboarding finish (seed: \(seedSampleData))")
        
        guard let context = modelContext else {
            logger.error("Finish failed: modelContext is nil")
            saveError = "Internal Error: Database context not found."
            isSaving = false
            return
        }
        
        guard let settings = appSettings else {
            logger.error("Finish failed: appSettings is nil")
            saveError = "Internal Error: App settings not found."
            isSaving = false
            return
        }
        
        let businessName = name.trimmed
        let businessEmail = email.trimmed.nilIfEmpty
        let businessPhone = phone.trimmed.nilIfEmpty
        let businessAddress = address.trimmed.nilIfEmpty
        let currentCurrency = currentCurrency
        let currentPIN = pin.filter(\.isNumber)
        let useBiometrics = biometricsEnabled && isBiometricsAvailable

        guard businessNameValidationMessage == nil else {
            saveError = businessNameValidationMessage
            isSaving = false
            return
        }
        guard regionalValidationMessage == nil else {
            saveError = regionalValidationMessage
            isSaving = false
            return
        }
        guard AppSettings.isValidPIN(currentPIN), currentPIN == confirmPin.filter(\.isNumber) else {
            saveError = "Your PIN is incomplete. Enter the same 4 digits in both fields."
            isSaving = false
            return
        }

        do {
            var descriptor = FetchDescriptor<BusinessConfig>()
            descriptor.fetchLimit = 1
            let config = try context.fetch(descriptor).first ?? BusinessConfig()

            config.name = businessName
            config.email = businessEmail
            config.phone = businessPhone
            config.address = businessAddress
            config.logoData = logoData
            config.isSetupComplete = true

            if config.modelContext == nil {
                context.insert(config)
            }

            // Persist BusinessConfig immediately on main so the @Query in RootView
            // re-evaluates and can dismiss onboarding. Heavier work (catalog seed,
            // demo data, summary rebuilds) runs off-main to avoid stalling the UI.
            try context.save()

            let container = context.container
            await Task.detached(priority: .userInitiated) {
                let bg = ModelContext(container)
                DataMigrations.ensureServiceCatalog(in: bg)
                DataMigrations.ensureMessageTemplates(in: bg)
                if seedSampleData {
                    try? DemoDataSeeder.seedIfNeeded(in: bg)
                }
                if bg.hasChanges {
                    try? bg.save()
                }
            }.value

            settings.isLockEnabled = true
            settings.isBiometricLockEnabled = useBiometrics
            settings.autoLockOnBackground = lockOnBackgroundEnabled
            settings.autoLockAfterInactivity = autoLockAfterInactivityEnabled
            settings.currencySymbol = currentCurrency
            settings.businessName = businessName
            settings.isChecklistDismissed = false
            settings.hasConfiguredPrices = seedSampleData
            settings.hasAddedFirstClient = seedSampleData
            settings.hasCompletedFirstVisit = seedSampleData

            guard settings.changePIN(to: currentPIN) else {
                throw ValidationError.custom(message: "The selected PIN could not be saved.")
            }

            TelemetryService.shared.track(event: "onboarding_finished", parameters: ["seedSampleData": String(seedSampleData)])

            Formatters.updateCurrencySymbol(currentCurrency)
            HapticManager.notify(.success)
            isSaving = false
            onComplete()
        } catch {
            logger.error("Failed to complete onboarding: \(error.localizedDescription, privacy: .public)")
            saveError = "Setup could not be saved. Please try again."
            isSaving = false
        }
    }
}
