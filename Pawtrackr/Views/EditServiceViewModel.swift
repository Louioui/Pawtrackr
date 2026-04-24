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
    
    private func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError.custom(message: "Service name cannot be empty.")
        }
        
        if let p = price, p < 0 {
            throw ValidationError.custom(message: "Price cannot be negative.")
        }
        
        if duration <= 0 {
            throw ValidationError.custom(message: "Duration must be at least 1 minute.")
        }
    }

    func save() async throws {
        try validate()
        
        let serviceToSave: Service
        if let service = service {
            serviceToSave = service
        } else {
            // Check for duplicate service name on creation
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            // Note: repository doesn't have findByName yet, but we can add it if needed
            // For now, let's just use fetchAll and filter
            let all = try await repository.fetchAllServices()
            if all.contains(where: { $0.name.lowercased() == trimmedName.lowercased() }) {
                throw ValidationError.custom(message: "A service with this name already exists.")
            }
            serviceToSave = Service(name: trimmedName)
        }
        
        serviceToSave.rename(name)
        serviceToSave.setCategory(category)
        serviceToSave.setBasePrice(price)
        serviceToSave.setEnabled(isEnabled)
        serviceToSave.isPackage = isPackage
        serviceToSave.setDefaultDurationMinutes(duration)
        serviceToSave.setSystemIcon(systemIcon)
        
        try await repository.saveService(serviceToSave)
    }
}
