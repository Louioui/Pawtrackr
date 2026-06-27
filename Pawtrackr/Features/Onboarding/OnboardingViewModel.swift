import Foundation
import Observation
import SwiftData
import OSLog
import SwiftUI

@Observable
@MainActor
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
            case .welcome:
                return NSLocalizedString("onboarding.step.welcome", value: "Welcome", comment: "")
            case .businessProfile:
                return NSLocalizedString("onboarding.step.business_profile", value: "Business Profile", comment: "")
            case .regional:
                return NSLocalizedString("onboarding.step.regional", value: "Regional Info", comment: "")
            case .security:
                return NSLocalizedString("onboarding.step.security", value: "Security", comment: "")
            case .permissions:
                return NSLocalizedString("onboarding.step.permissions", value: "Permissions", comment: "")
            case .warmStart:
                return NSLocalizedString("onboarding.step.finish", value: "Finish", comment: "")
            }
        }
    }

    var currentStep: Step = .welcome
    var name: String = "" { didSet { saveDraft() } }
    var email: String = "" { didSet { saveDraft() } }
    var phone: String = "" { didSet { saveDraft() } }
    var address: String = "" { didSet { saveDraft() } }
    var logoData: Data? = nil { didSet { saveDraft() } }
    var pin: String = "" {
        didSet {
            // Typing a PIN cancels a prior "skip" choice so finish() doesn't
            // silently leave the app passcode-free after the user changed their mind.
            if !pin.isEmpty { pinSkipped = false }
            saveDraft()
        }
    }
    var confirmPin: String = "" { didSet { saveDraft() } }
    /// User chose to set up the app without a PIN (passcode-free). Defaults false so
    /// existing validation/tests still require a matching 4-digit PIN by default.
    var pinSkipped: Bool = false { didSet { saveDraft() } }
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
            "pin": pin, "confirmPin": confirmPin, "pinSkipped": pinSkipped,
            "biometricsEnabled": biometricsEnabled,
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
        pinSkipped = draft["pinSkipped"] as? Bool ?? false
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
    
    /// Skips PIN setup entirely: the app will run passcode-free. Clears any
    /// partially-entered PIN and advances past the security step.
    func skipPIN() {
        pin = ""
        confirmPin = ""
        pinSkipped = true
        HapticManager.impact(.light)
        nextStep()
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
            if pinSkipped { return true }
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
            return NSLocalizedString("onboarding.action.get_started", value: "Get Started", comment: "")
        case .permissions:
            return NSLocalizedString("onboarding.action.review_setup", value: "Review Setup", comment: "")
        default:
            return NSLocalizedString("common.continue", value: "Continue", comment: "")
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
        name.trimmed.isEmpty
            ? NSLocalizedString("onboarding.validation.business_name", value: "Add your business name to continue.", comment: "")
            : nil
    }

    var regionalValidationMessage: String? {
        let trimmedEmail = email.trimmed
        guard !trimmedEmail.isEmpty else { return nil }
        // Use a more inclusive but standard regex
        let emailRegEx = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPred = NSPredicate(format:"SELF MATCHES %@", emailRegEx)
        return emailPred.evaluate(with: trimmedEmail)
            ? nil
            : NSLocalizedString("onboarding.validation.email", value: "Enter a valid email address (e.g., hello@business.com).", comment: "")
    }

    var securityValidationMessage: String? {
        let normalizedPIN = pin.filter(\.isNumber)
        let normalizedConfirm = confirmPin.filter(\.isNumber)

        if (!pin.isEmpty && normalizedPIN != pin) || (!confirmPin.isEmpty && normalizedConfirm != confirmPin) {
            return NSLocalizedString("onboarding.validation.pin_numbers_only", value: "PIN must use numbers only.", comment: "")
        }
        if !pin.isEmpty && normalizedPIN.count < 4 {
            return NSLocalizedString("onboarding.validation.pin_four_digits", value: "PIN must be 4 digits.", comment: "")
        }
        if !confirmPin.isEmpty && normalizedConfirm.count < 4 {
            return NSLocalizedString("onboarding.validation.confirm_pin", value: "Confirm your 4-digit PIN.", comment: "")
        }
        if normalizedPIN.count == 4 && normalizedConfirm.count == 4 && normalizedPIN != normalizedConfirm {
            return NSLocalizedString("onboarding.validation.pin_mismatch", value: "PINs do not match.", comment: "")
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
            return NSLocalizedString("onboarding.biometric.face_id_title", value: "Face ID Unlock", comment: "")
        case .touchID:
            return NSLocalizedString("onboarding.biometric.touch_id_title", value: "Touch ID Unlock", comment: "")
        case .unavailable:
            return NSLocalizedString("onboarding.biometric.unavailable_title", value: "Biometric Unlock (currently unavailable)", comment: "")
        case .none:
            return NSLocalizedString("onboarding.biometric.default_title", value: "Biometric Unlock", comment: "")
        }
    }

    var biometricSubtitle: String {
        switch biometrics.biometricType() {
        case .faceID, .touchID:
            return NSLocalizedString("onboarding.biometric.available_subtitle", value: "Use biometrics alongside your PIN for faster unlock.", comment: "")
        case .unavailable:
            return NSLocalizedString("onboarding.biometric.unavailable_subtitle", value: "Biometrics are temporarily unavailable on this device. Sign in with your PIN.", comment: "")
        case .none:
            return NSLocalizedString("onboarding.biometric.none_subtitle", value: "This device does not have biometric unlock available right now.", comment: "")
        }
    }
    
    // MARK: - Actions

    @MainActor
    @discardableResult
    func finish(seedSampleData: Bool, onComplete: @escaping () -> Void) async -> Task<Void, Never>? {
        guard !isSaving else { return nil }
        isSaving = true
        // Safety net: isSaving is always cleared regardless of which path exits.
        defer { isSaving = false }
        saveError = nil
        await Task.yield()

        logger.info("Starting onboarding finish (seed: \(seedSampleData))")

        guard let context = modelContext else {
            logger.error("Finish failed: modelContext is nil")
            saveError = NSLocalizedString("onboarding.error.internal_context", value: "Internal Error: Database context not found.", comment: "")
            return nil
        }

        guard let settings = appSettings else {
            logger.error("Finish failed: appSettings is nil")
            saveError = NSLocalizedString("onboarding.error.internal_settings", value: "Internal Error: App settings not found.", comment: "")
            return nil
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
            return nil
        }
        guard regionalValidationMessage == nil else {
            saveError = regionalValidationMessage
            return nil
        }
        let pinMatches = AppSettings.isValidPIN(currentPIN) && currentPIN == confirmPin.filter(\.isNumber)
        guard pinSkipped || pinMatches else {
            saveError = NSLocalizedString("onboarding.validation.pin_incomplete", value: "Your PIN is incomplete. Enter the same 4 digits in both fields.", comment: "")
            return nil
        }

        // Before writing BusinessConfig, let any pre-existing config syncing down
        // from iCloud land first. The fetch-first below then UPDATES that imported
        // config instead of inserting a duplicate (protects a returning user who
        // reinstalled and tapped through onboarding). For a genuine new user this
        // returns almost immediately — the launch first-sync watchdog has long
        // since settled while they filled in the form.
        if CloudKitMonitor.shared.accountState.isAvailable {
            await CloudKitMonitor.shared.awaitFirstSyncSettled(timeout: .seconds(5))
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

            // Persist BusinessConfig so @Query in RootView re-evaluates and
            // can dismiss onboarding. This save is small and fast.
            try context.save()

            // Apply settings (and PIN, unless the user opted out) before kicking
            // off background work. When the PIN is skipped the app runs lock-free.
            settings.isLockEnabled = !pinSkipped
            settings.isBiometricLockEnabled = pinSkipped ? false : useBiometrics
            settings.autoLockOnBackground = lockOnBackgroundEnabled
            settings.autoLockAfterInactivity = autoLockAfterInactivityEnabled
            settings.currencySymbol = currentCurrency
            settings.businessName = businessName
            settings.isChecklistDismissed = false
            settings.hasConfiguredPrices = seedSampleData
            settings.hasAddedFirstClient = seedSampleData
            settings.hasCompletedFirstVisit = seedSampleData
            settings.hasSeenAppTour = false

            if !pinSkipped {
                guard settings.changePIN(to: currentPIN) else {
                    throw ValidationError.custom(message: NSLocalizedString("onboarding.error.pin_save_failed", value: "The selected PIN could not be saved.", comment: ""))
                }
            }
            // Note: when pinSkipped, lock is disabled above so the stored PIN is
            // never consulted. Enabling App Lock later in Settings prompts for a PIN.

            // Catalog seed, demo data, and summary rebuilds are optional and
            // can be slow (multiple DB saves + potential SQLite write contention
            // with CloudKit sync). Fire-and-forget so the spinner clears
            // immediately and the user enters the app while seeding finishes
            // in the background.
            let container = context.container
            let backgroundTask = Task.detached(priority: .userInitiated) {
                let bg = ModelContext(container)
                DataMigrations.ensureServiceCatalog(in: bg)
                DataMigrations.ensureMessageTemplates(in: bg)
                // `ensureServiceCatalog` above already seeds the full starter
                // catalog (Bath, Haircut, packages, add-ons) with no default
                // price in BOTH paths, so Start-Fresh users are never left
                // without services. We intentionally do NOT insert an extra
                // "Basic Groom" service here: it duplicated the catalog and
                // re-introduced a hard-coded $50 default price, contradicting
                // the catalog's user-entered-price design.
                if seedSampleData {
                    do {
                        try DemoDataSeeder.seedIfNeeded(in: bg)
                    } catch {
                        Logger.database.error("Demo data seed failed during onboarding: \(error.localizedDescription, privacy: .public)")
                    }
                }
                if bg.hasChanges {
                    try? bg.save()
                }
                
                await MainActor.run {
                    onComplete()
                }
            }

            TelemetryService.shared.track(event: "onboarding_finished", parameters: ["seedSampleData": String(seedSampleData)])

            clearDraft()
            Formatters.updateCurrencySymbol(currentCurrency)
            HapticManager.notify(.success)
            
            return backgroundTask
        } catch {
            logger.error("Failed to complete onboarding: \(error.localizedDescription, privacy: .public)")
            saveError = NSLocalizedString("onboarding.error.save_failed", value: "Setup could not be saved. Please try again.", comment: "")
            return nil
        }
    }
}
