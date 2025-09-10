//
//  Formatters.swift
//  Pawtrackr
//
//  Centralized, @MainActor-isolated formatters and helpers used across the app.
//  IMPORTANT: There is NO `moneyString` here to avoid redeclaration conflicts.
//  Use `Decimal.moneyString` from `Decimal+Money.swift` for ergonomic UI.
//

import Foundation

@MainActor
enum Formatters {

    // MARK: - Currency

    /// Shared currency formatter (thread-unsafe → isolated on the main actor).
    static let currency: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = .current
        f.numberStyle = .currency
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        // Banker's rounding is applied when *computing* values; formatting just displays.
        return f
    }()

    /// Convenience: build a currency string without exposing a `moneyString` redeclaration.
    static func currencyString(_ value: Decimal) -> String {
        currency.string(from: value as NSDecimalNumber) ?? "$0.00"
    }

    /// Parse a user-entered currency string into Decimal.
    /// Accepts plain numbers ("12.34"), localized currency ("$12.34"), or sloppy input ("$ 12, 34").
    static func parseCurrency(_ raw: String) -> Decimal? {
        // Try strict parse with current locale first
        if let n = currency.number(from: raw) {
            return n.decimalValue.roundedMoney()
        }

        // Fallback: strip everything except digits and locale decimal separator
        let decSep = Locale.current.decimalSeparator ?? "."
        // Allow digits and the current locale's decimal separator.
        let allowed = CharacterSet(charactersIn: "0123456789" + decSep)
        let compact = raw.unicodeScalars.filter { allowed.contains($0) }
        let cleaned = String(String.UnicodeScalarView(compact))

        // If there's more than one decimal separator, keep the first and drop the rest.
        var normalized = cleaned
        if decSep != "." {
            normalized = normalized.replacingOccurrences(of: decSep, with: ".")
        }
        let parts = normalized.split(separator: ".", omittingEmptySubsequences: false)
        let sanitized: String = {
            switch parts.count {
            case 0:
                return "0"
            case 1:
                return String(parts[0])
            default:
                // Join only first two segments -> "12" + "." + "34xxxx" (we keep all fractional digits, rounding happens later)
                return String(parts[0]) + "." + parts[1...].joined()
            }
        }()

        guard let dec = Decimal(string: sanitized) else { return nil }
        return dec.roundedMoney()
    }

    // MARK: - ISO 8601

    /// ISO 8601 formatter for exporting/importing timestamps.
    static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    // MARK: - Human Date/Time

    /// Medium date + short time for a single timestamp.
    static let dateTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.doesRelativeDateFormatting = false
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    /// Medium date, no time.
    static let dateOnly: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.doesRelativeDateFormatting = false
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    /// Short time only.
    static let timeOnly: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    // MARK: - Helpers

    /// "Jan 2, 2025 · 10:00 AM – 11:15 AM" (same day)
    /// "Jan 2, 2025 10:00 AM – Jan 3, 2025 9:40 AM" (spans days)
    static func dateRangeString(from start: Date, to end: Date) -> String {
        let cal = Calendar.current
        if cal.isDate(start, inSameDayAs: end) {
            return "\(dateOnly.string(from: start)) · \(timeOnly.string(from: start)) – \(timeOnly.string(from: end))"
        } else {
            return "\(dateTime.string(from: start)) – \(dateTime.string(from: end))"
        }
    }

    /// Human duration like "1h 32m" or abbreviated "1h32m".
    static func durationString(from start: Date, to end: Date, abbreviated: Bool = false) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60

        func part(_ value: Int, _ unit: String) -> String? {
            guard value > 0 else { return nil }
            return abbreviated ? "\(value)\(unit.first!)" : "\(value)\(unit)"
        }

        // Prioritize hours/minutes; show seconds only if < 1m total.
        if h > 0 {
            return [part(h, "h"), part(m, "m")].compactMap { $0 }.joined(separator: abbreviated ? "" : " ")
        } else if m > 0 {
            return [part(m, "m")].compactMap { $0 }.joined()
        } else {
            // Under a minute
            return abbreviated ? "\(s)s" : "\(s)s"
        }
    }
}
