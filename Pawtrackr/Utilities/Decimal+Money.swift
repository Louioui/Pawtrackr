//
//  Decimal+Money.swift
//  Pawtrackr
//
//  Updated by assistant on 8/19/25.
//
//  Notes:
//  - USD-only formatting for display
//  - Robust parsing for inputs like "$1,234.56", "1 234,56", "(1,234.56)", "123-"
//  - Bankers rounding to 2 fraction digits for money math
//

import Foundation

// MARK: - Money operators with arithmetic-like precedence

precedencegroup AdditionLike {
    associativity: left
    higherThan: AssignmentPrecedence
}

precedencegroup MultiplicationLike {
    associativity: left
    higherThan: AdditionLike
}

infix operator +~ : AdditionLike
infix operator -~ : AdditionLike
infix operator *~ : MultiplicationLike

// MARK: - Decimal (money helpers)

public extension Decimal {
    /// Formats the decimal using USD currency (always shows 2 fraction digits for USD).
    var moneyString: String {
        Decimal.usdFormatter.string(from: NSDecimalNumber(decimal: self.rounded())) ?? self.formatted(.currency(code: "USD"))
    }

    /// Returns a copy rounded to `scale` fraction digits (bankers rounding by default).
    func rounded(scale: Int = 2, mode: NSDecimalNumber.RoundingMode = .bankers) -> Decimal {
        var value = self
        var result = Decimal()
        NSDecimalRound(&result, &value, scale, mode)
        return result
    }

    /// Adds two Decimals with 2-decimal rounding (useful for totals).
    static func +~ (lhs: Decimal, rhs: Decimal) -> Decimal { (lhs + rhs).rounded() }

    /// Subtracts two Decimals with 2-decimal rounding.
    static func -~ (lhs: Decimal, rhs: Decimal) -> Decimal { (lhs - rhs).rounded() }

    /// Multiplies two Decimals with 2-decimal rounding.
    static func *~ (lhs: Decimal, rhs: Decimal) -> Decimal { (lhs * rhs).rounded() }

    /// Overloads for common integer math (avoids Double).
    static func +~ (lhs: Decimal, rhs: Int) -> Decimal { lhs +~ Decimal(rhs) }
    static func -~ (lhs: Decimal, rhs: Int) -> Decimal { lhs -~ Decimal(rhs) }
    static func *~ (lhs: Decimal, rhs: Int) -> Decimal { lhs *~ Decimal(rhs) }

    /// Convert to whole cents (rounded).
    var cents: Int {
        let rounded = self.rounded(scale: 2)
        return NSDecimalNumber(decimal: rounded * 100).intValue
    }

    /// Construct from whole cents.
    static func fromCents(_ cents: Int) -> Decimal {
        Decimal(cents) / 100
    }

    /// Sum and round an array of money values.
    static func sum(_ values: [Decimal]) -> Decimal {
        values.reduce(0 as Decimal, +~)
    }

    // MARK: Private

    /// USD-only NumberFormatter (autoupdating locale for separators, USD for code; 2 fraction digits).
    private static let usdFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = .autoupdatingCurrent
        f.currencyCode = "USD"
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        f.generatesDecimalNumbers = true
        return f
    }()
}

// MARK: - String → Decimal parsing (robust)

public extension String {
    /// Attempts to parse a currency/number string into Decimal.
    /// - Important: Interprets currency as **USD**. Respects user's separators via `locale`.
    /// - Handles: localized formats, NBSP, grouping, parentheses negatives like "(1 234,56)", and trailing negative "123-".
    func asDecimal(locale: Locale = .autoupdatingCurrent) -> Decimal? {
        // 1) Direct Decimal initializer (fast path)
        if let d = Decimal(string: self, locale: locale) { return d }

        // 2) Lenient currency formatter (USD)
        let currency = NumberFormatter()
        currency.numberStyle = .currency
        currency.locale = locale
        currency.isLenient = true     // FIX: renamed property
        currency.currencyCode = "USD"
        if let n = currency.number(from: self) { return n.decimalValue }

        // 3) Lenient decimal formatter
        let decimal = NumberFormatter()
        decimal.numberStyle = .decimal
        decimal.locale = locale
        decimal.isLenient = true      // FIX: renamed property
        if let n = decimal.number(from: self) { return n.decimalValue }

        // 4) Manual cleanup fallback
        let decSep = decimal.decimalSeparator ?? "."
        let grpSep = decimal.groupingSeparator ?? ","

        var s = self.replacingOccurrences(of: "\u{00A0}", with: " ")
                     .trimmingCharacters(in: .whitespacesAndNewlines)

        var isNegative = false
        // Parentheses negative: "(1,234.56)"
        if s.first == "(", s.last == ")" {
            isNegative = true
            s.removeFirst()
            s.removeLast()
        }
        // Trailing negative: "123-"
        if s.hasSuffix("-") {
            isNegative = true
            s.removeLast()
        }

        // Keep digits, decimal/grouping separators, and minus sign
        let keep = CharacterSet.decimalDigits.union(CharacterSet(charactersIn: decSep + grpSep + "-"))
        s = s.components(separatedBy: keep.inverted).joined()

        // Remove grouping separators and normalize decimal separator to '.'
        if !grpSep.isEmpty {
            s = s.replacingOccurrences(of: grpSep, with: "")
        }
        if decSep != "." {
            s = s.replacingOccurrences(of: decSep, with: ".")
        }

        if isNegative, !s.hasPrefix("-") {
            s = "-" + s
        }

        // Final parse
        return Decimal(string: s)
    }
}
