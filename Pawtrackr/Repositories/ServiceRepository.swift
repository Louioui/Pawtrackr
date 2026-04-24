//
//  ServiceRepository.swift
//  Pawtrackr
//

import Foundation
import SwiftData

@MainActor
protocol ServiceRepositoryProtocol: Sendable {
    func fetchEnabledServices() async throws -> [Service]
    func fetchAllServices() async throws -> [Service]
    func saveService(_ service: Service) async throws
    func deleteService(_ service: Service) async throws
}

@MainActor
final class ServiceRepository: ServiceRepositoryProtocol {
    private let modelContext: ModelContext
    
    init(modelContainer: ModelContainer) {
        self.modelContext = modelContainer.mainContext
    }
    
    func fetchEnabledServices() async throws -> [Service] {
        let descriptor = FetchDescriptor<Service>(
            predicate: #Predicate { $0.isEnabled == true },
            sortBy: [SortDescriptor(\.name)]
        )
        return try modelContext.fetch(descriptor)
    }
    
    func fetchAllServices() async throws -> [Service] {
        let descriptor = FetchDescriptor<Service>(
            sortBy: [SortDescriptor(\.name)]
        )
        return try modelContext.fetch(descriptor)
    }
    
    func saveService(_ service: Service) async throws {
        if service.modelContext == nil {
            modelContext.insert(service)
        }
        try modelContext.save()
    }
    
    func deleteService(_ service: Service) async throws {
        modelContext.delete(service)
        try modelContext.save()
    }
}
