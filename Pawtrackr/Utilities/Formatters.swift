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

    /// Locale-aware currency for display (e.g., "$65" / "€65").
    static let currency: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = .current
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 0
        f.usesGroupingSeparator = true
        return f
    }()

    /// A plain decimal formatter suitable for editing text fields (no currency symbol).
    /// Keeps grouping separators for readability and clamps to 2 fraction digits.
    static let currencyEditing: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = .current
        f.usesGroupingSeparator = true
        f.groupingSize = 3
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 0
        return f
    }()

    /// Convenience to format a Decimal as currency using the current locale.
    static func currencyString(_ value: Decimal, nilPlaceholder: String = "—") -> String {
        let n = NSDecimalNumber(decimal: value)
        return currency.string(from: n) ?? nilPlaceholder
    }

    /// Formats a Decimal for an editing text field (no currency symbol).
    /// Falls back to a culture-agnostic numeric string if formatting fails.
    static func currencyEditingString(for value: Decimal) -> String {
        let n = NSDecimalNumber(decimal: value)
        return currencyEditing.string(from: n) ?? n.stringValue
    }

    /// Parses a user-entered currency / decimal string into Decimal.
    /// - Handles localized decimal separators, ignores all non-digit/sep chars.
    /// - Accepts inputs like "$65", "65,00", "1 234,50", "1,234.5", etc.
    static func parseCurrency(_ raw: String) -> Decimal? {
        // Normalize to the current locale's decimal separator
        let locale = Locale.current
        let decimalSep = locale.decimalSeparator ?? "."
        let altDecimalSep = decimalSep == "." ? "," : "."
        // Strip everything except digits and separators, then unify to current sep
        let filtered = raw
            .filter { $0.isNumber || $0 == Character(".") || $0 == Character(",") || $0 == Character("\u{00A0}") || $0 == " " }
            .replacingOccurrences(of: "\u{00A0}", with: "") // non‑breaking space
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: altDecimalSep, with: decimalSep)

        // Try NumberFormatter first (respects locale grouping)
        if let number = currencyEditing.number(from: filtered) {
            return number.decimalValue
        }

        // Fallback: naive Decimal init after forcing '.' as separator
        let canonical = filtered.replacingOccurrences(of: decimalSep, with: ".")
        return Decimal(string: canonical)
    }

    /// Parse a generic decimal (locale-aware). Alias to `parseCurrency` for clarity.
    static func parseDecimal(_ raw: String) -> Decimal? {
        parseCurrency(raw)
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

    /// ISO8601 formatter for persistence / diagnostics.
    static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    // MARK: - Relative time

    static let relativeAbbreviated: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated // e.g., "2h ago"
        return f
    }()

    static let relativeSpelledOut: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .spellOut // e.g., "two hours ago"
        return f
    }()

    // MARK: - Duration / TimeInterval

    /// Formats a duration between two dates as "2h 15m" or "8m".
    static func durationString(from start: Date, to end: Date = Date()) -> String {
        durationString(seconds: max(0, Int(end.timeIntervalSince(start))))
    }

    /// Formats seconds as "1h 03m" or "5m" / "37s".
    static func durationString(seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60

        if h > 0 { return String(format: "%dh %02dm", h, m) }
        if m > 0 { return String(format: "%dm", m) }
        return String(format: "%ds", s)
    }

    // MARK: - Phone (display helpers)

    /// Lightweight US phone display helper for 10-digit inputs (e.g., "(555) 123-4567").
    /// Returns nil if it cannot confidently format.
    static func displayPhoneUS(_ raw: String) -> String? {
        let digits = raw.filter(\.isNumber)
        guard digits.count == 10 else { return nil }
        let a = digits.prefix(3)
        let b = digits.dropFirst(3).prefix(3)
        let c = digits.suffix(4)
        return "(\(a)) \(b)-\(c)"
    }
}

// MARK: - Convenience extensions
extension Decimal {
    /// Formats the decimal using the app currency formatter.
    var asCurrency: String { Formatters.currencyString(self) }
}

extension Decimal {
    /// Formats the decimal for an editing field (no currency symbol).
    var asCurrencyEditing: String { Formatters.currencyEditingString(for: self) }
}

extension Date {
    /// Returns a short date+time string (locale-aware).
    var shortDateTime: String { Formatters.dateTimeShort.string(from: self) }

    /// Returns a medium date string (no time).
    var mediumDate: String { Formatters.dateOnlyMedium.string(from: self) }

    /// Returns a short time string (no date).
    var shortTime: String { Formatters.timeOnlyShort.string(from: self) }
}
