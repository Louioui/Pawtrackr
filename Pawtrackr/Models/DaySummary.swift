//
//  DaySummary.swift
//  Pawtrackr
//
//  Lightweight per-day aggregates to keep Insights fast at large scale.
//

import Foundation
import SwiftData

@Model
final class DaySummary {
    // Start-of-day (00:00) in the current calendar/timezone when computed
    // Defaults for CloudKit compatibility.
    var day: Date = Date()
    var revenue: Decimal = Decimal.zero
    var visitCount: Int = 0

    init(day: Date, revenue: Decimal, visitCount: Int) {
        self.day = day
        self.revenue = revenue
        self.visitCount = visitCount
    }
}

