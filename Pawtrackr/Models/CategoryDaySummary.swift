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
    var day: Date
    var categoryRaw: String
    var count: Int

    init(day: Date, categoryRaw: String, count: Int) {
        self.day = day
        self.categoryRaw = categoryRaw
        self.count = count
    }
}

