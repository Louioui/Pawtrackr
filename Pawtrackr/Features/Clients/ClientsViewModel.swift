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

        let filter = selectedFilter
        let sort = sortOption
        refreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                // The whole book, searched, filtered and ordered off the main
                // actor. Only IDs come back, and the grid builds just the
                // cards on screen, so a big book costs the main actor little.
                let list = try await repository.fetchClientList(query: trimmedSearch, filter: filter, sort: sort)
                guard !Task.isCancelled else { return }

                // One card per client whatever a repository returns: a
                // repeated ID also breaks the grid's identity.
                var listed = Set<PersistentIdentifier>()
                let inProgress = list.inProgress
                    .filter { listed.insert($0).inserted }
                    .compactMap { self.modelContext.model(for: $0) as? Client }
                let others = list.others
                    .filter { listed.insert($0).inserted }
                    .compactMap { self.modelContext.model(for: $0) as? Client }

                self.inProgressClients = inProgress
                self.otherClients = others

                self.fetchOffset = others.count
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

    /// The list's order (see `ClientListOrdering`).
    static func sorted(_ clients: [Client], by option: SortOption) -> [Client] {
        ClientListOrdering.sorted(clients, by: option)
    }

    /// Waits for a debounced search, the fetch started by the most recent
    /// `fetchClients()` (or a filter/sort change) and any Load More. Lets
    /// tests read the lists without sleeping.
    func waitForPendingFetch() async {
        await searchTask?.value
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
            let alreadyListed = resetOffset ? [] : Set(otherClients.map(\.persistentModelID))
            let newPage = pageIDs
                .filter { !alreadyListed.contains($0) }
                .compactMap { self.modelContext.model(for: $0) as? Client }

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
