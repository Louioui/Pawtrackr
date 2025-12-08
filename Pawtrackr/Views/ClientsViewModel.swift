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
        searchTask?.cancel()
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Reset state
        fetchOffset = 0
        canLoadMore = false
        isLoadingMore = false
        inProgressClients = []
        otherClients = []
        errorMessage = nil

        // Fetch in-progress in one shot (small set), then page through others
        refreshInProgressClients(query: trimmedSearch)
        loadMoreOthers(query: trimmedSearch, resetOffset: true)
    }

    func loadMore() {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        loadMoreOthers(query: trimmedSearch, resetOffset: false)
    }

    private func loadMoreOthers(query: String, resetOffset: Bool) {
        if isLoadingMore { return }
        if !resetOffset && !canLoadMore { return }
        isLoadingMore = true

        if resetOffset {
            fetchOffset = 0
            otherClients = []
        }

        let predicate = makePredicate(query: query, filterActive: .excludeActive)

        do {
            let sortDescriptors: [SortDescriptor<Client>] = [
                SortDescriptor(\.lastName, order: .forward),
                SortDescriptor(\.firstName, order: .forward)
            ]

            var descriptor = FetchDescriptor<Client>(predicate: predicate, sortBy: sortDescriptors)
            descriptor.fetchLimit = pageSize
            descriptor.fetchOffset = fetchOffset

            let page = try modelContext.fetch(descriptor)

            otherClients += page

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
        let pets = Array(client.pets)
        let visits = pets.flatMap { pet in Array(pet.visits) }
        let paymentDates = visits.compactMap { $0.payment?.paidAt }
        let visitActivityDates = visits.map { $0.endedAt ?? $0.startedAt }

        for visit in visits {
            visit.items.forEach { modelContext.delete($0) }
            if let payment = visit.payment {
                modelContext.delete(payment)
            }
        }

        modelContext.delete(client)

        do {
            try modelContext.save()

            let cal = Calendar.current
            var affectedDays: Set<Date> = []
            for date in paymentDates { affectedDays.insert(cal.startOfDay(for: date)) }
            for date in visitActivityDates { affectedDays.insert(cal.startOfDay(for: date)) }
            for day in affectedDays {
                SummaryUpdater.rebuildDay(for: day, in: modelContext)
            }
        } catch {
            errorMessage = "Failed to delete client: \(error.localizedDescription)"
        }
    }

    // MARK: - Private Helpers

    private func refreshInProgressClients(query: String) {
        let predicate = makePredicate(query: query, filterActive: .onlyActive)

        do {
            let descriptor = FetchDescriptor<Client>(predicate: predicate)
            let results = try modelContext.fetch(descriptor)
            inProgressClients = results.sorted { $0.sortKeyMostRecentVisit > $1.sortKeyMostRecentVisit }
        } catch {
            errorMessage = "Failed to fetch clients: \(error.localizedDescription)"
        }
    }

    private enum ActiveFilter {
        case onlyActive
        case excludeActive
        case none
    }

    private func makePredicate(query: String, filterActive: ActiveFilter) -> Predicate<Client>? {
        let hasQuery = !query.isEmpty

        switch (filterActive, hasQuery) {
        case (.onlyActive, true):
            return #Predicate<Client> { client in
                client.pets.contains { pet in pet.visits.contains { visit in visit.endedAt == nil } } &&
                (
                    client.firstName.localizedStandardContains(query) ||
                    client.lastName.localizedStandardContains(query) ||
                    (client.phone != nil && client.phone!.localizedStandardContains(query)) ||
                    client.pets.contains { $0.name.localizedStandardContains(query) }
                )
            }
        case (.onlyActive, false):
            return #Predicate<Client> { client in
                client.pets.contains { pet in pet.visits.contains { visit in visit.endedAt == nil } }
            }
        case (.excludeActive, true):
            return #Predicate<Client> { client in
                !client.pets.contains { pet in pet.visits.contains { visit in visit.endedAt == nil } } &&
                (
                    client.firstName.localizedStandardContains(query) ||
                    client.lastName.localizedStandardContains(query) ||
                    (client.phone != nil && client.phone!.localizedStandardContains(query)) ||
                    client.pets.contains { $0.name.localizedStandardContains(query) }
                )
            }
        case (.excludeActive, false):
            return #Predicate<Client> { client in
                !client.pets.contains { pet in pet.visits.contains { visit in visit.endedAt == nil } }
            }
        case (.none, true):
            return #Predicate<Client> { client in
                client.firstName.localizedStandardContains(query) ||
                client.lastName.localizedStandardContains(query) ||
                (client.phone != nil && client.phone!.localizedStandardContains(query)) ||
                client.pets.contains { $0.name.localizedStandardContains(query) }
            }
        case (.none, false):
            return nil
        }
    }
}
