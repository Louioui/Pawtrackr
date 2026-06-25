//
//  EditServiceViewModel.swift
//  Pawtrackr
//
//  Created by Assistant on 2025-12-05.
//

import SwiftUI
import SwiftData

@Observable
@MainActor
class EditServiceViewModel {
    var service: Service?
    
    var name: String = ""
    var price: Decimal?
    var category: Service.Category = .groom
    var isEnabled: Bool = true
    var isPackage: Bool = false
    var duration: Int = 30 // Default duration in minutes
    var systemIcon: String = "wrench.and.screwdriver"
    
    var appError: AppError? = nil

    private let repository: ServiceRepositoryProtocol

    init(modelContext: ModelContext, service: Service? = nil, repository: ServiceRepositoryProtocol? = nil) {
        self.repository = repository ?? ServiceRepository(modelContainer: modelContext.container)
        self.service = service
        
        if let service = service {
            self.name = service.name
            self.price = service.basePrice
            self.category = service.category ?? .groom
            self.isEnabled = service.isEnabled
            self.isPackage = service.isPackage
            self.duration = service.defaultDurationMinutes ?? 30
            self.systemIcon = service.systemIcon ?? "wrench.and.screwdriver"
        }
    }
    
    private func validate(trimmedName: String) throws {
        guard !trimmedName.isEmpty else {
            throw ValidationError.custom(message: AppLocalization.localized("service.validation.name_empty", value: "Service name cannot be empty."))
        }
        
        if let p = price, p < 0 {
            throw ValidationError.custom(message: AppLocalization.localized("service.validation.price_negative", value: "Price cannot be negative."))
        }
        
        if duration <= 0 {
            throw ValidationError.custom(message: AppLocalization.localized("service.validation.duration_min", value: "Duration must be at least 1 minute."))
        }
    }

    func save() async throws {
        let trimmedName = TextInputLimits.clamped(name, to: TextInputLimits.name)
        let trimmedSystemIcon = TextInputLimits.limited(systemIcon.trimmingCharacters(in: .whitespacesAndNewlines), to: TextInputLimits.shortText)
        try validate(trimmedName: trimmedName)
        let serviceToSave: Service

        if let service {
            // Editing existing — only run the duplicate check when the name
            // actually changed. Otherwise we'd reject every save of an
            // unchanged service against itself. Comparing case-insensitively
            // matches the rule used at creation time.
            if service.name.lowercased() != trimmedName.lowercased() {
                let all = try await repository.fetchAllServices()
                let editingID = service.persistentModelID
                if all.contains(where: { $0.persistentModelID != editingID && $0.name.lowercased() == trimmedName.lowercased() }) {
                    throw ValidationError.custom(message: AppLocalization.localized("service.validation.duplicate", value: "A service with this name already exists."))
                }
            }
            serviceToSave = service
        } else {
            // New service — straightforward duplicate check.
            let all = try await repository.fetchAllServices()
            if all.contains(where: { $0.name.lowercased() == trimmedName.lowercased() }) {
                throw ValidationError.custom(message: AppLocalization.localized("service.validation.duplicate", value: "A service with this name already exists."))
            }
            serviceToSave = Service(name: trimmedName)
        }

        serviceToSave.rename(trimmedName)
        serviceToSave.setCategory(category)
        serviceToSave.setBasePrice(price)
        serviceToSave.setEnabled(isEnabled)
        serviceToSave.isPackage = isPackage
        serviceToSave.setDefaultDurationMinutes(duration)
        serviceToSave.setSystemIcon(trimmedSystemIcon)

        try await repository.saveService(serviceToSave)
    }
}
