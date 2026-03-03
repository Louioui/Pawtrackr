//
//  Decimal+Money.swift
//  Pawtrackr
//
//  Money-safe arithmetic helpers and ergonomic formatting for Decimal.
//

import Foundation

// MARK: - Banker's Rounding (financial-safe)

public extension Decimal {
    /// Returns a copy rounded to 2 fractional digits using banker's rounding (.bankers).
    func roundedMoney(scale: Int = 2) -> Decimal {
        var value = self
        var result = Decimal()
        NSDecimalRound(&result, &value, scale, .bankers)
        return result
    }

    /// Human-friendly currency string using the shared currency formatter.
    /// NOTE: The actual formatter lives in `Formatters.currency`.
    @MainActor
    var moneyString: String {
        Formatters.currency.string(from: self as NSDecimalNumber) ?? "$0.00"
    }
}

// MARK: - Money-safe operators

infix operator +~ : AdditionPrecedence
infix operator *~ : MultiplicationPrecedence

/// Money-safe addition that rounds to 2 decimals using banker's rounding.
public func +~ (lhs: Decimal, rhs: Decimal) -> Decimal {
    (lhs + rhs).roundedMoney()
}

/// Money-safe multiplication that rounds to 2 decimals using banker's rounding.
public func *~ (lhs: Decimal, rhs: Decimal) -> Decimal {
    (lhs * rhs).roundedMoney()
}

// MARK: - Convenience initializers

public extension Decimal {
    /// Initialize from any numeric type safely.
    init<T: BinaryInteger>(_ value: T) {
        // Avoid recursive init calls and preserve precision when possible.
        if let parsed = Decimal(string: String(value)) {
            self = parsed
        } else {
            self = NSDecimalNumber(value: Double(value)).decimalValue
        }
    }

    init<T: BinaryFloatingPoint>(_ value: T) {
        // Avoid recursive init calls and guard against non-finite values.
        if value.isFinite, let parsed = Decimal(string: String(describing: value)) {
            self = parsed
        } else if value.isFinite {
            self = NSDecimalNumber(value: Double(value)).decimalValue
        } else {
            self = .zero
        }
    }
}
