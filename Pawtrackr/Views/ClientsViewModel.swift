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
    enum Filter: String, CaseIterable {
        case all = "All"
        case active = "Active"
        case overdue = "Overdue"
        case missingInfo = "Missing Info"

        var displayName: String {
            switch self {
            case .all:
                return NSLocalizedString("clients.filter.all", value: "All", comment: "")
            case .active:
                return NSLocalizedString("clients.filter.active", value: "Active", comment: "")
            case .overdue:
                return NSLocalizedString("clients.filter.overdue", value: "Overdue", comment: "")
            case .missingInfo:
                return NSLocalizedString("clients.filter.missing_info", value: "Missing Info", comment: "")
            }
        }
    }

    enum SortOption: String, CaseIterable {
        case name = "Name"
        case lastVisit = "Last Visit"
        case newest = "Newest"

        var displayName: String {
            switch self {
            case .name:
                return NSLocalizedString("clients.sort.name", value: "Name", comment: "")
            case .lastVisit:
                return NSLocalizedString("clients.sort.last_visit", value: "Last Visit", comment: "")
            case .newest:
                return NSLocalizedString("clients.sort.newest", value: "Newest", comment: "")
            }
        }
    }

    // MARK: - Published Properties
    var inProgressClients: [Client] = []
    var otherClients: [Client] = []
    var needsAttentionClients: [Client] = []
    
    var searchText = "" {
        didSet { scheduleFetch() }
    }
    
    var selectedFilter: Filter = .all {
        didSet { fetchClients() }
    }

    var sortOption: SortOption = .name {
        didSet { fetchClients() }
    }

    var inProgressCount: Int { inProgressClients.count }
    var canLoadMore: Bool = false
    var isLoadingMore: Bool = false
    var appError: AppError? = nil
    
    // MARK: - Private Properties
    private let modelContext: ModelContext
    private let repository: ClientRepositoryProtocol
    private var searchTask: Task<Void, Never>? = nil
    private var refreshTask: Task<Void, Never>? = nil
    private var loadMoreTask: Task<Void, Never>? = nil
    private var deleteTask: Task<Void, Never>? = nil
    private var cancellables: Set<AnyCancellable> = []
    private var pageSize: Int = 100
    private var fetchOffset: Int = 0
    
    // MARK: - Lifecycle
    init(modelContext: ModelContext, repository: ClientRepositoryProtocol? = nil) {
        self.modelContext = modelContext
        self.repository = repository ?? ClientRepository(modelContainer: modelContext.container)
        fetchClients() // Initial fetch

        // Listen for specific events that change the client list rather than
        // every ModelContext.didSave. The previous implementation refetched
        // on every save anywhere in the app — including unrelated saves
        // (visit photos, dashboard reloads, summary updates) — causing
        // 5–10× redundant fetches per checkout.
        let center = NotificationCenter.default
        let names: [Notification.Name] = [.clientDidCreate, .visitDidComplete, .visitDidStart]
        for name in names {
            center.publisher(for: name)
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.fetchClients() }
                .store(in: &cancellables)
        }
    }
    
    // MARK: - Data Fetching
    private func scheduleFetch() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300)) // Debounce search
            guard !Task.isCancelled else { return }
            self?.fetchClients()
        }
    }
    
    func fetchClients() {
        searchTask?.cancel()
        refreshTask?.cancel()
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        isLoadingMore = false
        appError = nil

        refreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                // 1. Fetch Active/In-Progress Clients
                let inProgressIDs = try await repository.fetchActiveClients(query: trimmedSearch)
                guard !Task.isCancelled else { return }
                
                var inProgress = inProgressIDs.compactMap { self.modelContext.model(for: $0) as? Client }

                // 2. Fetch Others based on filter
                let (pageIDs, _) = try await repository.fetchInactiveClients(query: trimmedSearch, limit: 1000, offset: 0)
                guard !Task.isCancelled else { return }
                
                var others = pageIDs.compactMap { self.modelContext.model(for: $0) as? Client }

                // Apply Smart Filters
                switch selectedFilter {
                case .all:
                    break
                case .active:
                    others = [] // Handled by inProgress
                case .overdue:
                    inProgress = []
                    others = others.filter { client in
                        (client.pets ?? []).contains { $0.isOverdue }
                    }
                case .missingInfo:
                    inProgress = inProgress.filter { $0.phone == nil || $0.email == nil }
                    others = others.filter { $0.phone == nil || $0.email == nil }
                }

                // Apply Sorting
                let sortedInProgress = sortClients(inProgress)
                let sortedOthers = sortClients(others)

                // Identify "Needs Attention" (Overdue but not active)
                self.needsAttentionClients = sortedOthers.filter { client in
                    (client.pets ?? []).contains { $0.isOverdue }
                }

                self.inProgressClients = sortedInProgress
                self.otherClients = sortedOthers
                
                self.fetchOffset = self.otherClients.count
                self.canLoadMore = false // For now, we fetch up to 1000 and handle locally for speed with filters
                self.isLoadingMore = false
            } catch {
                guard !Task.isCancelled else { return }
                appError = .database(error.localizedDescription)
                canLoadMore = false
                isLoadingMore = false
            }
        }
    }

    private func sortClients(_ clients: [Client]) -> [Client] {
        switch sortOption {
        case .name:
            return clients.sorted { $0.fullName.localizedStandardCompare($1.fullName) == .orderedAscending }
        case .lastVisit:
            return clients.sorted { ($0.lastVisitDate ?? .distantPast) > ($1.lastVisitDate ?? .distantPast) }
        case .newest:
            return clients.sorted { $0.createdAt > $1.createdAt }
        }
    }

    func loadMore() {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        loadMoreTask?.cancel()
        loadMoreTask = Task { [weak self] in
            guard let self else { return }
            await self.loadMoreOthers(query: trimmedSearch, resetOffset: false)
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
            let (pageIDs, hasMore) = try await repository.fetchInactiveClients(query: query, limit: pageSize, offset: fetchOffset)
            let newPage = pageIDs.compactMap { self.modelContext.model(for: $0) as? Client }
            
            if resetOffset {
                otherClients = newPage
            } else {
                otherClients += newPage
            }

            fetchOffset += newPage.count
            canLoadMore = hasMore
            isLoadingMore = false
        } catch {
            appError = .database(error.localizedDescription)
            canLoadMore = false
            isLoadingMore = false
        }
    }

    func deleteClient(_ client: Client) {
        let clientID = client.persistentModelID
        deleteTask?.cancel()
        deleteTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await repository.deleteClient(id: clientID)
                self.fetchClients()
            } catch {
                self.appError = .database(error.localizedDescription)
            }
        }
    }
}
