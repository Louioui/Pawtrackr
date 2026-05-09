//
//  OnboardingViewModel.swift
//  Pawtrackr
//
//  Manages the state and logic for the multi-step onboarding journey.
//

import SwiftUI
import Observation
import SwiftData
import OSLog

#if canImport(UserNotifications)
import UserNotifications
#endif

@Observable
final class OnboardingViewModel {
    enum Step: Int, CaseIterable {
        case welcome
        case businessProfile
        case regional
        case security
        case permissions
        case warmStart
        
        var title: String {
            switch self {
            case .welcome: return "Welcome"
            case .businessProfile: return "Your Business"
            case .regional: return "Regional Settings"
            case .security: return "Security"
            case .permissions: return "Preferences"
            case .warmStart: return "Ready to Start"
            }
        }
    }
    
    // MARK: - State
    var currentStep: Step = .welcome
    
    // Business Profile
    var name: String = ""
    var logoData: Data?
    
    // Regional/Contact
    var email: String = ""
    var phone: String = ""
    var address: String = ""
    var currencySymbol: String = "$"
    
    // Security
    var pin: String = ""
    var confirmPin: String = ""
    
    // Permissions
    var notificationsEnabled = false
    var biometricsEnabled = false
    
    // Metadata
    var isSaving = false
    var saveError: String?
    
    private var modelContext: ModelContext?
    private var appSettings: AppSettings?
    private let logger = Logger(subsystem: "com.pawtrackr", category: "Onboarding")
    
    // MARK: - Init
    init(modelContext: ModelContext?, appSettings: AppSettings?) {
        self.modelContext = modelContext
        self.appSettings = appSettings
        self.currencySymbol = appSettings?.currencySymbol ?? "$"
    }
    
    // MARK: - Navigation
    func nextStep() {
        guard canGoNext else {
            HapticManager.notify(.error)
            return
        }
        
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
            return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .regional:
            return !email.isEmpty && email.contains("@")
        case .security:
            return pin.count == 4 && pin == confirmPin
        case .permissions:
            return true
        case .warmStart:
            return true
        }
    }
    
    // MARK: - Actions
    
    func requestNotifications() {
        #if canImport(UserNotifications)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { success, _ in
            Task { @MainActor in
                self.notificationsEnabled = success
            }
        }
        #else
        self.notificationsEnabled = true
        #endif
    }
    
    func requestBiometrics() {
        biometricsEnabled = true
    }
    
    @MainActor
    func finish(seedSampleData: Bool, onComplete: @escaping () -> Void) async {
        guard !isSaving else { return }
        isSaving = true
        saveError = nil
        
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
        
        // Move heavy operations to a background task to prevent UI freezing
        let businessName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let businessEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let businessPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let businessAddress = address.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let currentCurrency = currencySymbol
        let currentPin = pin
        let useBiometrics = biometricsEnabled
        let logo = logoData
        
        Task.detached(priority: .userInitiated) {
            do {
                // 1. Update App Settings
                await MainActor.run {
                    _ = settings.changePIN(to: currentPin)
                    settings.currencySymbol = currentCurrency
                    settings.businessName = businessName
                    settings.isBiometricLockEnabled = useBiometrics
                }
                
                // 2. Save Business Config
                let backgroundContext = ModelContext(context.container)
                let configs = try backgroundContext.fetch(FetchDescriptor<BusinessConfig>())
                let config = configs.first ?? BusinessConfig()
                
                config.name = businessName
                config.email = businessEmail
                config.phone = businessPhone
                config.address = businessAddress
                config.logoData = logo
                config.isSetupComplete = true
                
                if config.modelContext == nil {
                    backgroundContext.insert(config)
                }
                
                // 3. Seed Sample Data if requested
                if seedSampleData {
                    try UITestDataSeeder.seedIfNeeded(in: backgroundContext)
                    await MainActor.run {
                        settings.hasConfiguredPrices = true
                        settings.hasAddedFirstClient = true
                        settings.hasCompletedFirstVisit = true
                    }
                } else {
                    DataMigrations.ensureServiceCatalog(in: backgroundContext)
                    DataMigrations.ensureMessageTemplates(in: backgroundContext)
                }
                
                try backgroundContext.save()
                
                // 4. Finalize on Main Actor
                await MainActor.run {
                    Formatters.updateCurrencySymbol(currentCurrency)
                    HapticManager.notify(.success)
                    self.isSaving = false
                    onComplete()
                }
            } catch {
                let errorMsg = error.localizedDescription
                await MainActor.run {
                    self.logger.error("Failed to complete onboarding: \(errorMsg)")
                    self.saveError = "Setup could not be saved. Please try again."
                    self.isSaving = false
                }
            }
        }
    }
}
