import Foundation
import Observation
import SwiftData
import OSLog
import SwiftUI

@Observable
final class OnboardingViewModel {
    @ObservationIgnored private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "Onboarding")
    @ObservationIgnored private let biometrics = BiometricAuthenticator()
    @ObservationIgnored private var hasLoadedInitialState = false

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
    var name: String = "" { didSet { saveDraft() } }
    var email: String = "" { didSet { saveDraft() } }
    var phone: String = "" { didSet { saveDraft() } }
    var address: String = "" { didSet { saveDraft() } }
    var logoData: Data? = nil { didSet { saveDraft() } }
    var pin: String = "" { didSet { saveDraft() } }
    var confirmPin: String = "" { didSet { saveDraft() } }
    var biometricsEnabled: Bool = false { didSet { saveDraft() } }
    var lockOnBackgroundEnabled: Bool = true { didSet { saveDraft() } }
    var autoLockAfterInactivityEnabled: Bool = false { didSet { saveDraft() } }
    var currentCurrency: String = "$" { didSet { saveDraft() } }
    var isSaving: Bool = false
    var saveError: String?

    var currencySymbol: String {
        get { currentCurrency }
        set { currentCurrency = newValue }
    }
    
    private let draftKey = "com.pawtrackr.onboarding.draft"

    private func saveDraft() {
        let draft: [String: Any] = [
            "name": name, "email": email, "phone": phone, "address": address,
            "pin": pin, "confirmPin": confirmPin, "biometricsEnabled": biometricsEnabled,
            "lockOnBackgroundEnabled": lockOnBackgroundEnabled,
            "autoLockAfterInactivityEnabled": autoLockAfterInactivityEnabled,
            "currency": currentCurrency
        ]
        UserDefaults.standard.set(draft, forKey: draftKey)
    }

    private func loadDraft() {
        guard let draft = UserDefaults.standard.dictionary(forKey: draftKey) else { return }
        name = draft["name"] as? String ?? ""
        email = draft["email"] as? String ?? ""
        phone = draft["phone"] as? String ?? ""
        address = draft["address"] as? String ?? ""
        pin = draft["pin"] as? String ?? ""
        confirmPin = draft["confirmPin"] as? String ?? ""
        biometricsEnabled = draft["biometricsEnabled"] as? Bool ?? false
        lockOnBackgroundEnabled = draft["lockOnBackgroundEnabled"] as? Bool ?? true
        autoLockAfterInactivityEnabled = draft["autoLockAfterInactivityEnabled"] as? Bool ?? false
        currentCurrency = draft["currency"] as? String ?? "$"
    }

    private func clearDraft() {
        UserDefaults.standard.removeObject(forKey: draftKey)
    }

    // MARK: - Init
    init(modelContext: ModelContext?, appSettings: AppSettings?) {
        self.modelContext = modelContext
        self.appSettings = appSettings
        self.currentCurrency = appSettings?.currencySymbol ?? "$"
        self.lockOnBackgroundEnabled = appSettings?.autoLockOnBackground ?? true
        self.autoLockAfterInactivityEnabled = appSettings?.autoLockAfterInactivity ?? false
        self.biometricsEnabled = (appSettings?.isBiometricLockEnabled ?? false) && isBiometricsAvailable

        loadDraft()
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
        switch biometrics.biometricType() {
        case .faceID, .touchID:
            return true
        case .none, .unavailable:
            return false
        }
    }

    var biometricTitle: String {
        switch biometrics.biometricType() {
        case .faceID:
            return "Face ID Unlock"
        case .touchID:
            return "Touch ID Unlock"
        case .unavailable:
            return "Biometric Unlock (currently unavailable)"
        case .none:
            return "Biometric Unlock"
        }
    }

    var biometricSubtitle: String {
        switch biometrics.biometricType() {
        case .faceID, .touchID:
            return "Use biometrics alongside your PIN for faster unlock."
        case .unavailable:
            return "Biometrics are temporarily unavailable on this device. Sign in with your PIN."
        case .none:
            return "This device does not have biometric unlock available right now."
        }
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
            // Propagate save errors so the user sees "couldn't finish setup"
            // instead of being dropped into an empty dashboard with no idea
            // why their service catalog / templates / demo data didn't appear.
            try await Task.detached(priority: .userInitiated) {
                let bg = ModelContext(container)
                DataMigrations.ensureServiceCatalog(in: bg)
                DataMigrations.ensureMessageTemplates(in: bg)
                if seedSampleData {
                    do {
                        try DemoDataSeeder.seedIfNeeded(in: bg)
                    } catch {
                        // Demo data is optional — log and continue.
                        Logger.database.error("Demo data seed failed during onboarding: \(error.localizedDescription, privacy: .public)")
                    }
                }
                if !seedSampleData {
                    let defaultService = Service(
                        name: "Basic Groom",
                        category: .groom,
                        systemIcon: "scissors",
                        basePrice: Decimal(50),
                        defaultDurationMinutes: 60
                    )
                    bg.insert(defaultService)
                }

                if bg.hasChanges {
                    try bg.save()
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
            // Arm the post-onboarding feature tour for fresh installs.
            // (Default registered value is `true`, so existing users skip it.)
            settings.hasSeenAppTour = false

            guard settings.changePIN(to: currentPIN) else {
                throw ValidationError.custom(message: "The selected PIN could not be saved.")
            }

            TelemetryService.shared.track(event: "onboarding_finished", parameters: ["seedSampleData": String(seedSampleData)])

            clearDraft()
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
