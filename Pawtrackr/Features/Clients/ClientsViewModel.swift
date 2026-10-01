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

                // Each fetch below reads the open visits on its own, so a
                // check-in landing between them lists a client in both. One
                // card per client: a repeated ID also breaks the grid's identity.
                var listed = Set<PersistentIdentifier>()
                var inProgress = inProgressIDs
                    .filter { listed.insert($0).inserted }
                    .compactMap { self.modelContext.model(for: $0) as? Client }

                // 2. Fetch Others based on filter.
                // One bounded fetch, not pages: the smart filters and every sort
                // other than last name run in memory below, so they must see
                // the whole book. Paging a 100-row last-name window made
                // filters show false "none" states, sorts skip clients, and
                // Load More repeat rows (the repository pages raw rows that
                // still include in-progress clients).
                let (pageIDs, _) = try await repository.fetchInactiveClients(query: trimmedSearch, limit: Self.clientListFetchLimit, offset: 0)
                guard !Task.isCancelled else { return }
                
                var others = pageIDs
                    .filter { listed.insert($0).inserted }
                    .compactMap { self.modelContext.model(for: $0) as? Client }

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
        Self.sorted(clients, by: sortOption)
    }

    /// The list's order. Every option ends in a total tiebreak (name, then
    /// creation date, then UUID), so two fetches of the same book list it the
    /// same way: equal keys (two "Maria Lopez", every client without a visit)
    /// used to keep whatever order the store returned and swap cards between
    /// refreshes. Names compare trimmed, ignoring case and accents
    /// (`localizedStandardCompare`); a blank last name sorts by the first name
    /// the card shows instead, and a client with no name at all goes last.
    /// Pet's Name uses the alphabetically first pet, the one the card lists
    /// first (`pets.first` has no defined order in SwiftData).
    static func sorted(_ clients: [Client], by option: SortOption) -> [Client] {
        // Keys are read once per client, not once per comparison: comparisons
        // would otherwise fault the pets relationship O(n log n) times.
        let keys = clients.map(ClientSortKey.init)
        return keys.sorted { a, b in
            let order: ComparisonResult
            switch option {
            case .lastName:
                order = a.blankName(b) ?? a.byLastName(b)
            case .firstName:
                order = a.blankName(b) ?? a.byFirstName(b)
            case .petName:
                order = ClientSortKey.blanksLast(a.petName == nil, b.petName == nil)
                    .then(ClientSortKey.compareText(a.petName ?? "", b.petName ?? ""))
                    .then(a.blankName(b) ?? a.byLastName(b))
            case .lastVisit:
                order = ClientSortKey.newestFirst(a.lastVisit ?? .distantPast, b.lastVisit ?? .distantPast)
                    .then(a.blankName(b) ?? a.byLastName(b))
            case .newest:
                order = ClientSortKey.newestFirst(a.createdAt, b.createdAt)
                    .then(a.blankName(b) ?? a.byLastName(b))
            }
            return order.then(a.byIdentity(b)) == .orderedAscending
        }
        .map(\.client)
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

/// One client's sort fields, read once (see `ClientsViewModel.sorted`).
private struct ClientSortKey {
    let client: Client
    let first: String
    let last: String
    let petName: String?
    let lastVisit: Date?
    let createdAt: Date
    let uuid: UUID

    init(_ client: Client) {
        self.client = client
        first = client.firstName.trimmed
        last = client.lastName.trimmed
        petName = (client.pets ?? [])
            .map(\.name.trimmed)
            .filter { !$0.isEmpty }
            .min { $0.localizedStandardCompare($1) == .orderedAscending }
        lastVisit = client.lastVisitDate
        createdAt = client.createdAt
        uuid = client.uuid
    }

    private var isNameless: Bool { first.isEmpty && last.isEmpty }

    /// Nameless clients after named ones; nil when that doesn't decide it.
    func blankName(_ other: ClientSortKey) -> ComparisonResult? {
        let order = Self.blanksLast(isNameless, other.isNameless)
        return order == .orderedSame ? nil : order
    }

    /// "Last First", or the first name alone when there is no last name.
    func byLastName(_ other: ClientSortKey) -> ComparisonResult {
        let lhs = last.isEmpty ? (first, "") : (last, first)
        let rhs = other.last.isEmpty ? (other.first, "") : (other.last, other.first)
        return Self.compareText(lhs.0, rhs.0).then(Self.compareText(lhs.1, rhs.1))
    }

    /// "First Last", or the last name alone when there is no first name.
    func byFirstName(_ other: ClientSortKey) -> ComparisonResult {
        let lhs = first.isEmpty ? (last, "") : (first, last)
        let rhs = other.first.isEmpty ? (other.last, "") : (other.first, other.last)
        return Self.compareText(lhs.0, rhs.0).then(Self.compareText(lhs.1, rhs.1))
    }

    /// The last resort, so no two clients ever compare equal. Plain `<` on
    /// the UUID: the localized comparison reads digit runs as numbers and
    /// could call two different UUIDs equal.
    func byIdentity(_ other: ClientSortKey) -> ComparisonResult {
        Self.compare(createdAt, other.createdAt)
            .then(Self.compare(uuid.uuidString, other.uuid.uuidString))
    }

    /// As the list reads: case- and accent-insensitive, numbers by value.
    static func compareText(_ lhs: String, _ rhs: String) -> ComparisonResult {
        lhs.localizedStandardCompare(rhs)
    }

    static func compare<T: Comparable>(_ lhs: T, _ rhs: T) -> ComparisonResult {
        lhs < rhs ? .orderedAscending : (lhs > rhs ? .orderedDescending : .orderedSame)
    }

    static func newestFirst(_ lhs: Date, _ rhs: Date) -> ComparisonResult {
        compare(rhs, lhs)
    }

    static func blanksLast(_ lhsBlank: Bool, _ rhsBlank: Bool) -> ComparisonResult {
        guard lhsBlank != rhsBlank else { return .orderedSame }
        return lhsBlank ? .orderedDescending : .orderedAscending
    }
}

private extension ComparisonResult {
    /// `self` unless it is a tie, then `next`.
    func then(_ next: @autoclosure () -> ComparisonResult) -> ComparisonResult {
        self == .orderedSame ? next() : self
    }
}
