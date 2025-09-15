
//
//  DataPruner.swift
//  Pawtrackr
//
//  Created by Gemini on 9/15/25.
//

import Foundation
import SwiftData

class DataPruner {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func pruneVisits(olderThan date: Date) throws {
        let predicate = #Predicate<Visit> { visit in
            visit.startedAt < date
        }
        try modelContext.delete(model: Visit.self, where: predicate)
    }
}
