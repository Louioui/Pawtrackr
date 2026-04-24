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
    var appError: AppError? = nil
    
    // MARK: - Private Properties
    private var modelContext: ModelContext
    private let repository: ClientRepositoryProtocol
    private var searchTask: Task<Void, Never>? = nil
    private var cancellables: Set<AnyCancellable> = []
    private var pageSize: Int = 100
    private var fetchOffset: Int = 0
    
    // MARK: - Lifecycle
    init(modelContext: ModelContext, repository: ClientRepositoryProtocol? = nil) {
        self.modelContext = modelContext
        self.repository = repository ?? ClientRepository(modelContainer: modelContext.container)
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
        searchTask?.cancel()
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Reset state
        fetchOffset = 0
        canLoadMore = false
        isLoadingMore = false
        inProgressClients = []
        otherClients = []
        appError = nil

        Task {
            await refreshInProgressClients(query: trimmedSearch)
            await loadMoreOthers(query: trimmedSearch, resetOffset: true)
        }
    }

    func loadMore() {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            await loadMoreOthers(query: trimmedSearch, resetOffset: false)
        }
    }

    private func loadMoreOthers(query: String, resetOffset: Bool) async {
        if isLoadingMore { return }
        if !resetOffset && !canLoadMore { return }
        isLoadingMore = true

        if resetOffset {
            fetchOffset = 0
        }

        do {
            let (page, hasMore) = try await repository.fetchInactiveClients(query: query, limit: pageSize, offset: fetchOffset)
            
            if resetOffset {
                otherClients = page
            } else {
                otherClients += page
            }

            fetchOffset += page.count
            canLoadMore = hasMore
            isLoadingMore = false
        } catch {
            appError = .database(error.localizedDescription)
            canLoadMore = false
            isLoadingMore = false
        }
        }

        func deleteClient(_ client: Client) {
        Task {
            do {
                try await repository.deleteClient(client)
                fetchClients() // Refresh list
            } catch {
                appError = .database(error.localizedDescription)
            }
        }
        }

        // MARK: - Private Helpers

        private func refreshInProgressClients(query: String) async {
        do {
            inProgressClients = try await repository.fetchActiveClients(query: query)
        } catch {
            appError = .database(error.localizedDescription)
        }
        }
        }
