//
//  ServiceManagementViewModel.swift
//  Pawtrackr
//
//  Created by Assistant on 2025-12-05.
//

import SwiftUI
import SwiftData

@Observable
@MainActor
class ServiceManagementViewModel {
    var services: [Service] = []
    var appError: AppError? = nil
    private let repository: ServiceRepositoryProtocol

    init(modelContext: ModelContext, repository: ServiceRepositoryProtocol? = nil) {
        self.repository = repository ?? ServiceRepository(modelContainer: modelContext.container)
        fetchServices()
    }

    func fetchServices() {
        Task {
            do {
                services = try await repository.fetchAllServices()
            } catch {
                appError = .database(error.localizedDescription)
                print("Failed to fetch services: \(error)")
            }
        }
    }

    func deleteService(_ service: Service) {
        Task {
            do {
                try await repository.deleteService(service)
                fetchServices()
            } catch {
                appError = .database(error.localizedDescription)
            }
        }
    }
}
