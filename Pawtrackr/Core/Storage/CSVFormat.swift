//
//  CSVFormat.swift
//  Pawtrackr
//
//  One way to write every CSV the app exports, so each file opens cleanly
//  in Numbers, Excel and Google Sheets:
//  - CRLF line endings (RFC 4180), and a UTF-8 byte order mark added when
//    the file is shared (`ExportDocument`), so Excel reads "José" right.
//  - Dates as yyyy-MM-dd and times as HH:mm, which every spreadsheet sorts
//    and filters as dates.
//  - Money as plain numbers ("1234.50"): no currency symbol, no grouping,
//    always a period, so columns can be summed.
//  - Text that can't run as a formula: a cell starting with =, +, -, @ or
//    a tab gets a leading apostrophe (OWASP's CSV injection advice).
//    Phone numbers are written as "(415) 555-0142", which needs none.
//
//  Everything here is safe off the main actor.
//

import Foundation

enum CSVFormat {
    static let lineBreak = "\r\n"

    /// One row: cells already formatted with the helpers below.
    static func line(_ cells: [String]) -> String {
        cells.joined(separator: ",")
    }

    /// A whole table or report, one row per line, ending with a line break.
    static func document(_ rows: [[String]]) -> String {
        rows.map(line).joined(separator: lineBreak) + lineBreak
    }

    /// Free text a person typed: quoted when needed, and kept from running
    /// as a spreadsheet formula.
    static func text(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "" }
        var safe = value
        if let first = safe.unicodeScalars.first, formulaTriggers.contains(first) {
            safe = "'" + safe
        }
        return safe.csvEscaped
    }

    private static let formulaTriggers: Set<Unicode.Scalar> = ["=", "+", "-", "@", "\t", "\r"]

    /// A phone number the way the app shows it, "(415) 555-0142", which
    /// spreadsheets keep as text. Stored numbers are "+14155550142", which
    /// Excel would turn into a number, dropping the "+". A number that
    /// isn't a US one stays as typed.
    static func phone(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "" }
        return text(PhoneUtils.display(value) ?? value)
    }

    /// Money as a plain number with two decimals: "1234.50".
    static func money(_ value: Decimal) -> String {
        moneyFormatter.string(from: value.roundedMoney() as NSDecimalNumber) ?? "0.00"
    }

    static func integer(_ value: Int) -> String {
        String(value)
    }

    /// A whole-number percentage of `part` over `whole`, or empty when there
    /// is nothing to compare with.
    static func percent(_ part: Decimal, of whole: Decimal) -> String {
        guard whole > .zero else { return "" }
        let ratio = NSDecimalNumber(decimal: part / whole).doubleValue
        return String(Int((ratio * 100).rounded()))
    }

    /// The change from `previous` to `current` in whole percent, or empty
    /// when the previous value is zero.
    static func change(from previous: Decimal, to current: Decimal) -> String {
        guard previous > .zero else { return "" }
        let ratio = NSDecimalNumber(decimal: (current - previous) / previous).doubleValue
        return String(Int((ratio * 100).rounded()))
    }

    // A new formatter per call: exports run on background tasks, and a
    // NumberFormatter shouldn't be shared between threads.
    private static var moneyFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }
}

/// Date and time cells in the formats every spreadsheet reads. Build one per
/// export: DateFormatter isn't meant to be shared across threads.
struct CSVDateFormats {
    private let dayFormatter: DateFormatter
    private let timeFormatter: DateFormatter
    private let monthFormatter: DateFormatter
    private let stampFormatter: DateFormatter

    init(timeZone: TimeZone = .current) {
        func make(_ format: String) -> DateFormatter {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = timeZone
            formatter.dateFormat = format
            return formatter
        }
        dayFormatter = make("yyyy-MM-dd")
        timeFormatter = make("HH:mm")
        monthFormatter = make("yyyy-MM")
        stampFormatter = make("yyyy-MM-dd HH:mm")
    }

    /// "2026-09-30", or empty.
    func day(_ date: Date?) -> String {
        date.map(dayFormatter.string(from:)) ?? ""
    }

    /// "14:05", or empty.
    func time(_ date: Date?) -> String {
        date.map(timeFormatter.string(from:)) ?? ""
    }

    /// "2026-09".
    func month(_ date: Date) -> String {
        monthFormatter.string(from: date)
    }

    /// "2026-09-30 14:05".
    func stamp(_ date: Date) -> String {
        stampFormatter.string(from: date)
    }
}
