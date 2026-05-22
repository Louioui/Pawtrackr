//
//  CategoryDaySummary.swift
//  Pawtrackr
//
//  Aggregated service category counts per day for fast Insights.
//

import Foundation
import SwiftData

@Model
final class CategoryDaySummary {
    // Defaults for CloudKit compatibility.
    var day: Date = Date()
    var categoryRaw: String = ""
    var count: Int = 0

    init(day: Date, categoryRaw: String, count: Int) {
        self.day = day
        self.categoryRaw = categoryRaw
        self.count = count
    }
}

