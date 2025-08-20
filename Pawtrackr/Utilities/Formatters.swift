//
//  Formatters.swift
//  Pawtrackr
//
//  Created by mac on 8/14/25.
//

import Foundation

/// Central place for commonly used formatters in Pawtrackr
enum Formatters {
    // MARK: - Numbers / Currency
    static let currency: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = .current
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 0
        return f
    }()

    /// Convenience to format a Decimal as currency using the current locale.
    static func currencyString(_ value: Decimal) -> String {
        let n = NSDecimalNumber(decimal: value)
        return currency.string(from: n) ?? "\(value)"
    }

    // MARK: - Dates
    static let dateTimeShort: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    static let dateOnlyMedium: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    static let timeOnlyShort: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    // MARK: - Relative time
    static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated // e.g., "2h ago"
        return f
    }()

    // MARK: - Duration (hh mm)
    /// Formats a duration between two dates as "2h 15m" or "8m".
    static func durationString(from start: Date, to end: Date = Date()) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}

// MARK: - Convenience extensions
extension Decimal {
    /// Formats the decimal using the app currency formatter.
    var asCurrency: String { Formatters.currencyString(self) }
}

extension Date {
    /// Returns a short date+time string (locale-aware).
    var shortDateTime: String { Formatters.dateTimeShort.string(from: self) }

    /// Returns a medium date string (no time).
    var mediumDate: String { Formatters.dateOnlyMedium.string(from: self) }

    /// Returns a short time string (no date).
    var shortTime: String { Formatters.timeOnlyShort.string(from: self) }
}
