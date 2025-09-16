//
//  VisitHistoryFetchDescriptorBuilder.swift
//  Pawtrackr
//
//  Created by Assistant on 2025-09-15.
//
//  Centralized helpers for building performant SwiftData queries when loading visit history.
//  The builder pushes filtering for dates, pets, and search tokens into the persistent store so
//  large datasets remain responsive.
//

import Foundation
import SwiftData

struct VisitHistoryFilter {
    var startDate: Date?
    var endDate: Date?
    var searchTokens: [String] = []
    var petUUIDs: Set<UUID> = []
    var visitUUIDs: Set<UUID> = []
    var fetchLimit: Int?
}

enum VisitHistoryFetchDescriptorBuilder {
    static func makeDescriptor(using filter: VisitHistoryFilter) -> FetchDescriptor<Visit> {
        var predicates: [NSPredicate] = [NSPredicate(format: "endedAt != nil")]

        if let start = filter.startDate {
            predicates.append(NSPredicate(format: "endedAt >= %@", start as NSDate))
        }
        if let end = filter.endDate {
            predicates.append(NSPredicate(format: "endedAt < %@", end as NSDate))
        }
        if !filter.petUUIDs.isEmpty {
            let uuids = filter.petUUIDs.map { $0 as NSUUID }
            predicates.append(NSPredicate(format: "pet.uuid IN %@", uuids))
        }
        if !filter.visitUUIDs.isEmpty {
            let uuids = filter.visitUUIDs.map { $0 as NSUUID }
            predicates.append(NSPredicate(format: "uuid IN %@", uuids))
        }

        for token in filter.searchTokens where !token.isEmpty {
            let tokenPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(format: "pet.name CONTAINS[cd] %@", token),
                NSPredicate(format: "pet.owner.firstName CONTAINS[cd] %@", token),
                NSPredicate(format: "pet.owner.lastName CONTAINS[cd] %@", token),
                NSPredicate(format: "note CONTAINS[cd] %@", token),
                NSPredicate(format: "ANY items.name CONTAINS[cd] %@", token),
                NSPredicate(format: "payment.externalReference CONTAINS[cd] %@", token)
            ])
            predicates.append(tokenPredicate)
        }

        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        var descriptor = FetchDescriptor<Visit>(predicate: predicate, sortBy: [SortDescriptor(\.endedAt, order: .reverse)])
        if let limit = filter.fetchLimit { descriptor.fetchLimit = limit }
        descriptor.includePendingChanges = true
        return descriptor
    }
}

