//
//  ClientsViewModel.swift
//  Pawtrackr
//


import SwiftUI
import SwiftData
import Combine
import OSLog

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
                return NSLocalizedString("clients.filter.overdue", value: "Needs Attention", comment: "")
            case .missingInfo:
                return NSLocalizedString("clients.filter.missing_info", value: "Missing Info", comment: "")
            }
        }
    }

    enum SortOption: String, CaseIterable {
        case lastName = "Last Name"
        case firstName = "First Name"
        case petName = "Pet's Name"
        case lastVisit = "Last Visit"
        case newest = "Newest"

        var displayName: String {
            switch self {
            case .lastName:
                return NSLocalizedString("clients.sort.last_name", value: "Last Name", comment: "")
            case .firstName:
                return NSLocalizedString("clients.sort.first_name", value: "First Name", comment: "")
            case .petName:
                return NSLocalizedString("clients.sort.pet_name", value: "Pet's Name", comment: "")
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

    var sortOption: SortOption = .lastName {
        didSet { fetchClients() }
    }

    var inProgressCount: Int { inProgressClients.count }
    var canLoadMore: Bool = false
    var isLoadingMore: Bool = false
    var appError: AppError? = nil
    
    // MARK: - Private Properties
    private let modelContext: ModelContext
    private let repository: ClientRepositoryProtocol
    private let eventBus: GlobalEventBus?
    private var searchTask: Task<Void, Never>? = nil
    private var refreshTask: Task<Void, Never>? = nil
    private var loadMoreTask: Task<Void, Never>? = nil
    private var deleteTask: Task<Void, Never>? = nil
    private var eventTask: Task<Void, Never>? = nil
    private var cancellables: Set<AnyCancellable> = []
    private var pageSize: Int = 100
    private var fetchOffset: Int = 0
    /// Clients the list loads per query. Filters and sorts run over this whole
    /// set in memory, so it is not a page size (see `fetchClients`).
    static let clientListFetchLimit = 1000

    // MARK: - Lifecycle
    init(modelContext: ModelContext, eventBus: GlobalEventBus? = nil, repository: ClientRepositoryProtocol? = nil) {
        self.modelContext = modelContext
        self.repository = repository ?? ClientRepository(modelContainer: modelContext.container)
        self.eventBus = eventBus
        fetchClients() // Initial fetch

        let center = NotificationCenter.default
        let names: [Notification.Name] = [.clientDidCreate, .visitDidComplete, .visitDidStart]
        for name in names {
            center.publisher(for: name)
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.fetchClients() }
                .store(in: &cancellables)
        }

        if let eventBus {
            let stream = eventBus.stream
            eventTask = Task { [weak self] in
                for await event in stream {
                    guard let self else { return }
                    if event == .refreshRequired {
                        self.fetchClients()
                    }
                }
            }
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
        // A Load More still in flight belongs to the previous query or sort.
        // Letting it finish would append rows that don't match the new list.
        loadMoreTask?.cancel()
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

                // 2. Fetch Others based on filter.
                // One bounded fetch, not pages: the smart filters and every sort
                // other than last name run in memory below, so they must see
                // the whole book. Paging a 100-row last-name window made
                // filters show false "none" states, sorts skip clients, and
                // Load More repeat rows (the repository pages raw rows that
                // still include in-progress clients).
                let (pageIDs, _) = try await repository.fetchInactiveClients(query: trimmedSearch, limit: Self.clientListFetchLimit, offset: 0)
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
                        (client.pets ?? []).contains { $0.needsAttention }
                    }
                case .missingInfo:
                    // The same rule as the profile's "Missing:" note.
                    inProgress = inProgress.filter(ClientMissingInfo.isIncomplete)
                    others = others.filter(ClientMissingInfo.isIncomplete)
                }

                // Apply Sorting
                let sortedInProgress = sortClients(inProgress)
                let sortedOthers = sortClients(others)

                // Identify "Needs Attention" (overdue and not yet cleared by outreach).
                self.needsAttentionClients = sortedOthers.filter { client in
                    (client.pets ?? []).contains { $0.needsAttention }
                }

                self.inProgressClients = sortedInProgress
                self.otherClients = sortedOthers
                
                self.fetchOffset = self.otherClients.count
                self.canLoadMore = false
                self.isLoadingMore = false
            } catch {
                guard !Task.isCancelled else { return }
                appError = .database(error.localizedDescription)
                canLoadMore = false
                isLoadingMore = false
            }
        }
    }

    func recordAttentionOutreach(for client: Client, method: String) {
        let petsToClear = (client.pets ?? []).filter { $0.needsAttention }
        guard !petsToClear.isEmpty else { return }

        do {
            for pet in petsToClear {
                pet.recordAttentionOutreach()
            }

            try modelContext.save()
            NotificationCenter.default.post(name: .serviceDidUpdate, object: nil)
            eventBus?.publish(.refreshRequired)
            fetchClients()
            Logger.ui.info("Client list cleared needs-attention flag for \(petsToClear.count, privacy: .public) pet(s) after \(method, privacy: .public)")
        } catch {
            appError = .database(error.localizedDescription)
            Logger.database.error("Local save failed: \(error.localizedDescription, privacy: .public)")
            Logger.database.error("Failed to record client-list attention outreach: \(String(describing: error))")
        }
    }

    private func sortClients(_ clients: [Client]) -> [Client] {
        switch sortOption {
        case .lastName:
            return clients.sorted { client1, client2 in
                let comparison = client1.lastName.localizedStandardCompare(client2.lastName)
                if comparison == .orderedSame {
                    return client1.firstName.localizedStandardCompare(client2.firstName) == .orderedAscending
                }
                return comparison == .orderedAscending
            }
            
        case .firstName:
            return clients.sorted { client1, client2 in
                let comparison = client1.firstName.localizedStandardCompare(client2.firstName)
                if comparison == .orderedSame {
                    return client1.lastName.localizedStandardCompare(client2.lastName) == .orderedAscending
                }
                return comparison == .orderedAscending
            }
            
        case .petName:
            return clients.sorted { client1, client2 in
                let pet1 = client1.pets?.first?.name ?? ""
                let pet2 = client2.pets?.first?.name ?? ""
                let comparison = pet1.localizedStandardCompare(pet2)
                if comparison == .orderedSame {
                    return client1.lastName.localizedStandardCompare(client2.lastName) == .orderedAscending
                }
                return comparison == .orderedAscending
            }
            
        case .lastVisit:
            return clients.sorted { ($0.lastVisitDate ?? .distantPast) > ($1.lastVisitDate ?? .distantPast) }
            
        case .newest:
            return clients.sorted { $0.createdAt > $1.createdAt }
        }
    }

    /// Waits for the fetch started by the most recent `fetchClients()` (or a
    /// filter/sort change) and any Load More. Lets tests read the lists
    /// without sleeping.
    func waitForPendingFetch() async {
        await refreshTask?.value
        await loadMoreTask?.value
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
            guard !Task.isCancelled else {
                isLoadingMore = false
                return
            }
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
