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
    private var modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        fetchServices()
    }

    func fetchServices() {
        do {
            let descriptor = FetchDescriptor<Service>(sortBy: [SortDescriptor(\.name)])
            services = try modelContext.fetch(descriptor)
        } catch {
            print("Failed to fetch services: \(error)")
        }
    }

    func deleteService(_ service: Service) {
        modelContext.delete(service)
        fetchServices()
    }
}
