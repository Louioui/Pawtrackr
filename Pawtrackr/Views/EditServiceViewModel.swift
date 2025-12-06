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
    
    var errorMessage: String?

    private var modelContext: ModelContext

    init(modelContext: ModelContext, service: Service? = nil) {
        self.modelContext = modelContext
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
    }

    func save() throws {
        try validate()
        
        let serviceToSave: Service
        if let service = service {
            serviceToSave = service
        } else {
            // Check for duplicate service name on creation
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let existing = try modelContext.fetch(FetchDescriptor<Service>(predicate: #Predicate { $0.name == trimmedName }))
            if !existing.isEmpty {
                throw ValidationError.custom(message: "A service with this name already exists.")
            }
            serviceToSave = Service(name: trimmedName)
            modelContext.insert(serviceToSave)
        }
        
        serviceToSave.rename(name)
        serviceToSave.setCategory(category)
        serviceToSave.setBasePrice(price)
        serviceToSave.setEnabled(isEnabled)
        serviceToSave.isPackage = isPackage
        serviceToSave.setDefaultDurationMinutes(duration)
        serviceToSave.setSystemIcon(systemIcon)
        
        try modelContext.save()
    }
}
