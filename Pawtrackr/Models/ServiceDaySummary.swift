//
//  ServiceDaySummary.swift
//  Pawtrackr
//
//  Aggregated service counts per day for fast Insights.
//

import Foundation
import SwiftData

@Model
final class ServiceDaySummary {
    // Defaults for CloudKit compatibility.
    var day: Date = Date()
    var serviceName: String = ""
    var count: Int = 0

    init(day: Date, serviceName: String, count: Int) {
        self.day = day
        self.serviceName = serviceName
        self.count = count
    }
}

