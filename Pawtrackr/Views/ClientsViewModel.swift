//
//  ClientsViewModel.swift
//  Pawtrackr
//
//  Created by Assistant on 2025-08-28.
//  Updated by Assistant on 2025-09-03
//

import SwiftUI
import SwiftData

@Observable
@MainActor
final class ClientsViewModel {
    // MARK: - Published Properties
    var inProgressClients: [Client] = []
    var otherClients: [Client] = []
    var searchText = "" {
        didSet { scheduleFetch() }
    }
    
    var inProgressCount: Int { inProgressClients.count }
    
    // MARK: - Private Properties
    private var modelContext: ModelContext
    private var searchTask: Task<Void, Never>? = nil
    
    // MARK: - Lifecycle
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        fetchClients() // Initial fetch
    }
    
    // MARK: - Data Fetching
    
    private func scheduleFetch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300)) // Debounce search
            guard !Task.isCancelled else { return }
            self.fetchClients()
        }
    }
    
    func fetchClients() {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // IMPROVEMENT: Build a predicate to filter in the database for better performance.
        // This is significantly more efficient than fetching all clients and filtering in memory.
        let predicate: Predicate<Client>?
        if trimmedSearch.isEmpty {
            predicate = nil // No filter, fetch all clients.
        } else {
            predicate = #Predicate<Client> { client in
                // Search by client's first or last name
                client.firstName.localizedStandardContains(trimmedSearch) ||
                client.lastName.localizedStandardContains(trimmedSearch) ||
                
                // Search by the name of any associated pet
                client.pets.filter { pet in
                    pet.name.localizedStandardContains(trimmedSearch)
                }.isEmpty == false ||
                
                // Search by phone number digits (assuming phone is stored normalized)
                (client.phone?.contains(trimmedSearch) ?? false)
            }
        }

        do {
            let sortDescriptors: [SortDescriptor<Client>] = [
                SortDescriptor(\.lastName, order: .forward),
                SortDescriptor(\.firstName, order: .forward)
            ]
            
            let descriptor = FetchDescriptor<Client>(predicate: predicate, sortBy: sortDescriptors)
            let filteredClients = try modelContext.fetch(descriptor)

            // Partition into in-progress vs. other clients using the centralized extension properties.
            // This assumes `hasActiveVisit` and `sortKeyMostRecentVisit`
            // have been moved to a `Client+Extensions.swift` file.
            self.inProgressClients = filteredClients
                .filter { $0.hasActiveVisit }
                .sorted { $0.sortKeyMostRecentVisit > $1.sortKeyMostRecentVisit }

            self.otherClients = filteredClients
                .filter { !$0.hasActiveVisit }
            
        } catch {
            print("Failed to fetch clients: \(error.localizedDescription)")
            self.inProgressClients = []
            self.otherClients = []
        }
    }
}
