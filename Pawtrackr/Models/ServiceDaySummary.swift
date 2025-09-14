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
    var day: Date
    var serviceName: String
    var count: Int

    init(day: Date, serviceName: String, count: Int) {
        self.day = day
        self.serviceName = serviceName
        self.count = count
    }
}

