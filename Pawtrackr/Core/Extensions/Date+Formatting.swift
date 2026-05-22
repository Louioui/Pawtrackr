//
//  Date+Formatting.swift
//  Pawtrackr
//
//  Small convenience helpers for human-readable date/time strings.
//

import Foundation

public extension Date {
    /// Medium date + short time string using the shared Formatters.
    @MainActor
    var shortDateTime: String {
        Formatters.dateTime.string(from: self)
    }
}

