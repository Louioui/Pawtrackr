import Foundation

@MainActor
enum ClientListOrdering {
    /// Sorts by the selected primary key, then owner name and stable UUID.
    /// Empty primary keys sort after named records without sentinel strings.
    static func sorted(_ clients: [Client], by option: ClientsViewModel.SortOption) -> [Client] {
        clients.sorted { lhs, rhs in
            switch option {
            case .lastName, .firstName:
                let left = option == .lastName ? [lhs.lastName, lhs.firstName] : [lhs.firstName, lhs.lastName]
                let right = option == .lastName ? [rhs.lastName, rhs.firstName] : [rhs.firstName, rhs.lastName]
                for (a, b) in zip(left, right) {
                    if let result = ascending(a, b) { return result }
                }
            case .petName:
                if let result = ascending(firstPetName(lhs), firstPetName(rhs)) { return result }
            case .lastVisit:
                let a = lhs.lastVisitDate ?? .distantPast
                let b = rhs.lastVisitDate ?? .distantPast
                if a != b { return a > b }
            case .newest:
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            }
            if let result = ascending(lhs.lastName, rhs.lastName) { return result }
            if let result = ascending(lhs.firstName, rhs.firstName) { return result }
            return lhs.uuid.uuidString < rhs.uuid.uuidString
        }
    }

    /// Returns the alphabetically first current pet, independent of relationship order.
    private static func firstPetName(_ client: Client) -> String {
        (client.pets ?? []).filter { $0.archivedAt == nil }.map { $0.name.trimmed }
            .filter { !$0.isEmpty }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }.first ?? ""
    }

    /// Returns nil for equal keys so callers can evaluate a stable secondary key.
    private static func ascending(_ a: String, _ b: String) -> Bool? {
        let left = a.trimmed
        let right = b.trimmed
        if left.isEmpty != right.isEmpty { return !left.isEmpty }
        let comparison = left.localizedStandardCompare(right)
        return comparison == .orderedSame ? nil : comparison == .orderedAscending
    }
}
