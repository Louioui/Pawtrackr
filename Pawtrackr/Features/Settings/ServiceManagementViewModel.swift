//
//  ServiceManagementViewModel.swift
//  Pawtrackr
//
//  Created by Assistant on 2025-12-05.
//

import SwiftUI
import SwiftData
import OSLog
import Combine

private final class SMVMObserverToken {
    private let token: NSObjectProtocol
    init(_ token: NSObjectProtocol) { self.token = token }
    deinit { NotificationCenter.default.removeObserver(token) }
}

@Observable
@MainActor
final class ServiceManagementViewModel {
    var services: [Service] = []
    var appError: AppError? = nil
    private let repository: ServiceRepositoryProtocol
    private var fetchTask: Task<Void, Never>?
    private var serviceUpdateObserver: SMVMObserverToken?

    init(modelContext: ModelContext, repository: ServiceRepositoryProtocol? = nil) {
        self.repository = repository ?? ServiceRepository(modelContainer: modelContext.container)
        fetchServices()

        // Repository posts .serviceDidUpdate after every save and delete.
        // Subscribing here keeps the list fresh regardless of where the
        // mutation originates: edit pushed via NavigationLink, add via
        // sheet, deletion, or eventually a CloudKit-driven sync from
        // another device that the repository routes through the same path.
        let token = NotificationCenter.default.addObserver(
            forName: .serviceDidUpdate, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.fetchServices()
            }
        }
        self.serviceUpdateObserver = SMVMObserverToken(token)
    }

    func fetchServices() {
        fetchTask?.cancel()
        fetchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let next = try await repository.fetchAllServices()
                guard !Task.isCancelled else { return }
                services = next
            } catch {
                guard !Task.isCancelled else { return }
                appError = .database(error.localizedDescription)
                Logger.serviceManagement.error("Failed to fetch services: \(String(describing: error))")
            }
        }
    }

    func deleteService(_ service: Service) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await repository.deleteService(service)
                // .serviceDidUpdate observer will refetch — no explicit
                // fetchServices() call needed here.
            } catch {
                appError = .database(error.localizedDescription)
                CloudKitMonitor.shared.reportLocalSaveError(error, operation: "deleting service")
                Logger.serviceManagement.error("Failed to delete service: \(String(describing: error))")
            }
        }
    }
}

private extension Logger {
    static let serviceManagement = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "ServiceManagement")
}
