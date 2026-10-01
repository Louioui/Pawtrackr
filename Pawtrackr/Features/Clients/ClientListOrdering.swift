//
//  ClientListOrdering.swift
//  Pawtrackr
//
//  The Clients list's order, outside the main actor so the background list
//  read (`ClientRepository.fetchClientList`) and the view model share it.
//

import Foundation

enum ClientListOrdering {
    /// The list's order. Every option ends in a total tiebreak (name, then
    /// creation date, then UUID), so two fetches of the same book list it the
    /// same way: equal keys (two "Maria Lopez", every client without a visit)
    /// used to keep whatever order the store returned and swap cards between
    /// refreshes. Names compare trimmed, ignoring case and accents
    /// (`localizedStandardCompare`); a blank last name sorts by the first name
    /// the card shows instead, and a client with no name at all goes last.
    /// Pet's Name uses the alphabetically first pet, the one the card lists
    /// first (`pets.first` has no defined order in SwiftData).
    static func sorted(_ clients: [Client], by option: ClientsViewModel.SortOption) -> [Client] {
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
}

/// One client's sort fields, read once (see `ClientListOrdering.sorted`).
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
