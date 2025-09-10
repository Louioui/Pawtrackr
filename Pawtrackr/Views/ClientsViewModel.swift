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
        
        // Keep DB predicate simple (no nested closures) and filter text in-memory
        let predicate: Predicate<Client>? = nil

        do {
            let sortDescriptors: [SortDescriptor<Client>] = [
                SortDescriptor(\.lastName, order: .forward),
                SortDescriptor(\.firstName, order: .forward)
            ]
            
            let descriptor = FetchDescriptor<Client>(predicate: predicate, sortBy: sortDescriptors)
            var filteredClients = try modelContext.fetch(descriptor)

            if !trimmedSearch.isEmpty {
                filteredClients = filteredClients.filter { client in
                    if client.firstName.localizedStandardContains(trimmedSearch) { return true }
                    if client.lastName.localizedStandardContains(trimmedSearch) { return true }
                    if let phone = client.phone, phone.localizedStandardContains(trimmedSearch) { return true }
                    if client.pets.contains(where: { $0.name.localizedStandardContains(trimmedSearch) }) { return true }
                    return false
                }
            }

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
