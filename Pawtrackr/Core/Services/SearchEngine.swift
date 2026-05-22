//
//  SearchEngine.swift
//  Pawtrackr
//
//  A high-performance utility for searching through collections of models.
//  Uses diacritic-insensitive, case-insensitive matching for a "Google-like" experience.
//

import Foundation

struct SearchEngine {

    /// Returns true if the query matches any of the provided fields.
    static func matches(_ query: String, in fields: [String?]) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }

        let needle = trimmed.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)

        for field in fields {
            guard let field = field, !field.isEmpty else { continue }
            let haystack = field.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            if haystack.contains(needle) {
                return true
            }
        }

        return false
    }

    /// Filters a collection of items based on a query and a dictionary of fields.
    /// Example: fields: ["n": client.fullName, "p": client.phone]
    static func smartFilter<T>(_ items: [T], query: String, fieldMap: (T) -> [String: String?]) -> [T] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }

        if trimmed.contains(":") {
            let parts = trimmed.split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                let prefix = parts[0].lowercased()
                let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                let needle = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)

                return items.filter { item in
                    let map = fieldMap(item)
                    if let fieldValue = map[prefix], let fieldValue = fieldValue {
                        let haystack = fieldValue.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                        return haystack.contains(needle)
                    }
                    return false
                }
            }
        }

        return filter(items, query: query) { item in
            Array(fieldMap(item).values)
        }
    }

    /// Filters a collection of items based on a query and a closure that extracts searchable fields.
    static func filter<T>(_ items: [T], query: String, fields: (T) -> [String?]) -> [T] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }

        return items.filter { item in
            matches(trimmed, in: fields(item))
        }
    }
}
