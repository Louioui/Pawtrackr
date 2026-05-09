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
        guard let next = Step(rawValue: currentStep.rawValue + 1) else { return }
        withAnimation {
            currentStep = next
        }
    }
    
    func previousStep() {
        guard let prev = Step(rawValue: currentStep.rawValue - 1) else { return }
        withAnimation {
            currentStep = prev
        }
    }
    
    var canGoNext: Bool {
        switch currentStep {
        case .welcome:
            return true
        case .businessProfile:
            return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .regional:
            return true
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
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { success, _ in
            Task { @MainActor in
                self.notificationsEnabled = success
            }
        }
    }
    
    func requestBiometrics() {
        // Biometrics activation logic usually happens in BiometricAuthenticator
        // Here we just toggle the preference to be saved later.
        biometricsEnabled = true
    }
    
    @MainActor
    func finish(seedSampleData: Bool, onComplete: @escaping () -> Void) async {
        guard let context = modelContext, let settings = appSettings else { return }
        
        isSaving = true
        saveError = nil
        
        do {
            // 1. Update App Settings (PIN, Currency, Permissions)
            _ = settings.changePIN(to: pin)
            settings.currencySymbol = currencySymbol
            settings.businessName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            settings.isBiometricLockEnabled = biometricsEnabled
            
            // 2. Save Business Config
            let fetchDescriptor = FetchDescriptor<BusinessConfig>()
            let configs = try context.fetch(fetchDescriptor)
            let config = configs.first ?? BusinessConfig()
            
            config.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            config.email = email.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            config.phone = phone.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            config.address = address.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            config.logoData = logoData
            config.isSetupComplete = true
            
            if config.modelContext == nil {
                context.insert(config)
            }
            
            // 3. Seed Sample Data if requested
            if seedSampleData {
                try UITestDataSeeder.seedIfNeeded(in: context)
                settings.hasConfiguredPrices = true
                settings.hasAddedFirstClient = true
                settings.hasCompletedFirstVisit = true
            } else {
                // Ensure basic services exist even for a fresh start
                DataMigrations.ensureServiceCatalog(in: context)
                DataMigrations.ensureMessageTemplates(in: context)
            }
            
            try context.save()
            
            // 4. Update Formatters
            Formatters.updateCurrencySymbol(currencySymbol)
            
            // Haptic Success
            HapticManager.notify(.success)
            
            onComplete()
        } catch {
            logger.error("Failed to complete onboarding: \(error.localizedDescription)")
            saveError = "Setup could not be saved. Please try again."
        }
        
        isSaving = false
    }
}

