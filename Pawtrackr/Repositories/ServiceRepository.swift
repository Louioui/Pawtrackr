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
        // Don't ship the SwiftData model itself across NotificationCenter — it's
        // not Sendable and listeners on other actors can crash or see invalidated
        // instances. Pass the persistentModelID via userInfo instead.
        NotificationCenter.default.post(
            name: .serviceDidUpdate,
            object: nil,
            userInfo: ["serviceID": service.persistentModelID]
        )
    }

    func deleteService(_ service: Service) async throws {
        let id = service.persistentModelID
        modelContext.delete(service)
        try modelContext.save()
        // Use the same notification for save+delete so existing listeners just
        // refetch on either signal. The serviceID + a `deleted` marker let
        // future-aware listeners distinguish without breaking current ones.
        NotificationCenter.default.post(
            name: .serviceDidUpdate,
            object: nil,
            userInfo: ["serviceID": id, "deleted": true]
        )
    }
}
