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
            // A newer refresh already replaced this one; don't read the store.
            guard let self, !Task.isCancelled else { return }
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

                let unique = Self.removingDuplicates(inProgress: inProgress, others: others)
                inProgress = unique.inProgress
                others = unique.others

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
        Self.sortClients(clients, by: sortOption)
    }

    /// One client's sort keys, read once per fetch instead of once per
    /// comparison (each read can fault a row or its pets).
    private struct SortEntry {
        let client: Client
        let lastFirst: [String]
        let firstLast: [String]
        let petName: String?
        let uuid: String
    }

    /// A total order over the list. Names compare word by word the way the
    /// card shows them, ignoring case, so "adams" sits with "Adams" and a
    /// client with only a first name sorts by it instead of jumping to the
    /// top. The pet sort uses the pet the card lists first (alphabetical),
    /// not `pets.first`, whose order SwiftData doesn't keep. Every sort ends
    /// on the UUID, so clients with the same name or date hold their places
    /// from one refresh to the next instead of swapping rows.
    static func sortClients(_ clients: [Client], by option: SortOption) -> [Client] {
        let entries = clients.map { client in
            let first = client.firstName.trimmed
            let last = client.lastName.trimmed
            let petName = (client.pets ?? [])
                .map { $0.name.trimmed }
                .filter { !$0.isEmpty }
                .min { $0.localizedStandardCompare($1) == .orderedAscending }
            return SortEntry(
                client: client,
                lastFirst: [last, first].filter { !$0.isEmpty },
                firstLast: [first, last].filter { !$0.isEmpty },
                petName: petName,
                uuid: client.uuid.uuidString
            )
        }

        func ordered(_ lhs: SortEntry, _ rhs: SortEntry, _ comparisons: [ComparisonResult]) -> Bool {
            for result in comparisons where result != .orderedSame {
                return result == .orderedAscending
            }
            return lhs.uuid < rhs.uuid
        }

        let sorted: [SortEntry]
        switch option {
        case .lastName:
            sorted = entries.sorted { ordered($0, $1, [compareNames($0.lastFirst, $1.lastFirst)]) }
        case .firstName:
            sorted = entries.sorted { ordered($0, $1, [compareNames($0.firstLast, $1.firstLast)]) }
        case .petName:
            sorted = entries.sorted {
                ordered($0, $1, [
                    compareMissingLast($0.petName, $1.petName) { $0.localizedStandardCompare($1) },
                    compareNames($0.lastFirst, $1.lastFirst)
                ])
            }
        case .lastVisit:
            sorted = entries.sorted {
                ordered($0, $1, [
                    // Most recent first; clients never seen go last.
                    compareMissingLast($0.client.lastVisitDate, $1.client.lastVisitDate) { lhs, rhs in
                        lhs == rhs ? .orderedSame : (lhs > rhs ? .orderedAscending : .orderedDescending)
                    },
                    compareNames($0.lastFirst, $1.lastFirst)
                ])
            }
        case .newest:
            sorted = entries.sorted {
                let lhs = $0.client.createdAt, rhs = $1.client.createdAt
                return ordered($0, $1, [
                    lhs == rhs ? .orderedSame : (lhs > rhs ? .orderedAscending : .orderedDescending),
                    compareNames($0.lastFirst, $1.lastFirst)
                ])
            }
        }
        return sorted.map(\.client)
    }

    /// Word-by-word, case-insensitive, numbers in numeric order. A record
    /// with no name at all goes after every named one.
    private static func compareNames(_ lhs: [String], _ rhs: [String]) -> ComparisonResult {
        if lhs.isEmpty != rhs.isEmpty { return lhs.isEmpty ? .orderedDescending : .orderedAscending }
        for (left, right) in zip(lhs, rhs) {
            let result = left.localizedStandardCompare(right)
            if result != .orderedSame { return result }
        }
        if lhs.count == rhs.count { return .orderedSame }
        return lhs.count < rhs.count ? .orderedAscending : .orderedDescending
    }

    private static func compareMissingLast<T>(_ lhs: T?, _ rhs: T?, _ compare: (T, T) -> ComparisonResult) -> ComparisonResult {
        guard let lhs else { return rhs == nil ? .orderedSame : .orderedDescending }
        guard let rhs else { return .orderedAscending }
        return compare(lhs, rhs)
    }

    /// Keeps the first occurrence of each client across both sections. The
    /// in-progress and "all" lists come from two separate store reads, so a
    /// visit starting or ending between them could put one client in both,
    /// and the same card would render twice until the next refresh.
    static func removingDuplicates(inProgress: [Client], others: [Client]) -> (inProgress: [Client], others: [Client]) {
        var seen = Set<PersistentIdentifier>()
        let uniqueInProgress = inProgress.filter { seen.insert($0.persistentModelID).inserted }
        let uniqueOthers = others.filter { seen.insert($0.persistentModelID).inserted }
        return (uniqueInProgress, uniqueOthers)
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
