//
//  ClientsViewModel.swift
//  Pawtrackr
//
//  Created by Assistant on 2025-08-28.
//  Updated by Assistant on 2025-09-03
//

import SwiftUI
import SwiftData
import Combine

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
    var canLoadMore: Bool = false
    var isLoadingMore: Bool = false
    var errorMessage: String? = nil
    
    // MARK: - Private Properties
    private var modelContext: ModelContext
    private var searchTask: Task<Void, Never>? = nil
    private var cancellables: Set<AnyCancellable> = []
    private var pageSize: Int = 100
    private var fetchOffset: Int = 0
    
    // MARK: - Lifecycle
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        fetchClients() // Initial fetch
        
        // Observe changes to the ModelContext to refresh client list
        NotificationCenter.default.publisher(for: ModelContext.didSave)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.fetchClients() }
            .store(in: &cancellables)
    }
    
    deinit { /* Combine cancellables auto-cancel on deinit */ }
    
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
        // Reset pagination and fetch first page
        fetchOffset = 0
        canLoadMore = false
        inProgressClients = []
        otherClients = []
        errorMessage = nil
        loadMore()
    }

    func loadMore() {
        // Prevent overlapping loads; allow first page even if canLoadMore is false
        if isLoadingMore { return }
        if fetchOffset > 0 && !canLoadMore { return }
        isLoadingMore = true
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        var predicate: Predicate<Client>?
        if !trimmedSearch.isEmpty {
            let query = trimmedSearch
            predicate = #Predicate<Client> { client in
                client.firstName.localizedStandardContains(query) ||
                client.lastName.localizedStandardContains(query) ||
                (client.phone != nil && client.phone!.localizedStandardContains(query)) ||
                client.pets.contains { $0.name.localizedStandardContains(query) }
            }
        }

        do {
            let sortDescriptors: [SortDescriptor<Client>] = [
                SortDescriptor(\.lastName, order: .forward),
                SortDescriptor(\.firstName, order: .forward)
            ]

            var descriptor = FetchDescriptor<Client>(predicate: predicate, sortBy: sortDescriptors)
            descriptor.fetchLimit = pageSize
            descriptor.fetchOffset = fetchOffset

            let page = try modelContext.fetch(descriptor)

            // Append and re-partition
            let newInProgress = page.filter { $0.hasActiveVisit }
                .sorted { $0.sortKeyMostRecentVisit > $1.sortKeyMostRecentVisit }
            let newOthers = page.filter { !$0.hasActiveVisit }

            self.inProgressClients += newInProgress
            self.otherClients += newOthers

            fetchOffset += page.count
            canLoadMore = page.count == pageSize
            isLoadingMore = false
        } catch {
            errorMessage = "Failed to fetch clients: \(error.localizedDescription)"
            canLoadMore = false
            isLoadingMore = false
        }
    }

    func deleteClient(_ client: Client) {
        modelContext.delete(client)
        do {
            try modelContext.save()
        } catch {
            errorMessage = "Failed to delete client: \(error.localizedDescription)"
        }
    }
}
