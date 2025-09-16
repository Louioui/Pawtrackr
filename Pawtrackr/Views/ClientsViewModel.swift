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
        
        var predicate: Predicate<Client>?
        if !trimmedSearch.isEmpty {
            predicate = #Predicate<Client> { client in
                client.firstName.localizedStandardContains(trimmedSearch) ||
                client.lastName.localizedStandardContains(trimmedSearch) ||
                (client.phone != nil && client.phone!.localizedStandardContains(trimmedSearch)) ||
                client.pets.contains { $0.name.localizedStandardContains(trimmedSearch) }
            }
        }

        do {
            let sortDescriptors: [SortDescriptor<Client>] = [
                SortDescriptor(\.lastName, order: .forward),
                SortDescriptor(\.firstName, order: .forward)
            ]
            
            var descriptor = FetchDescriptor<Client>(predicate: predicate, sortBy: sortDescriptors)
            // The fetch limit can be removed or adjusted, as the filtering is now much more efficient.
            // descriptor.fetchLimit = 2000 
            let filteredClients = try modelContext.fetch(descriptor)

            // Partitioning is now done on a much smaller, pre-filtered array.
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
