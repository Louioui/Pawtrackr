//
//  String+Extensions.swift
//  Pawtrackr
//
//  Created by mac on 9/5/25.
//

import Foundation

enum TextInputLimits {
    static let name = 64
    static let shortText = 64
    static let phone = 32
    static let email = 254
    static let address = 256
    static let notes = 1_000

    /// Returns `value` with leading/trailing whitespace removed and no more than `maxLength` user-visible characters.
    static func clamped(_ value: String, to maxLength: Int) -> String {
        limited(value.trimmed, to: maxLength)
    }

    /// Returns a trimmed, length-limited string, or `nil` when the resulting value is empty.
    static func clampedOptional(_ value: String, to maxLength: Int) -> String? {
        let clampedValue = clamped(value, to: maxLength)
        return clampedValue.isEmpty ? nil : clampedValue
    }

    /// Returns `value` with its original surrounding whitespace preserved but no more than `maxLength` user-visible characters.
    static func limited(_ value: String, to maxLength: Int) -> String {
        guard maxLength >= 0 else { return "" }
        guard value.count > maxLength else { return value }
        return String(value.prefix(maxLength))
    }
}

extension String {
    /// Returns the string with leading and trailing whitespace and newlines removed.
    var trimmed: String {
        self.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
    
    /// Returns a version of the string formatted for names (e.g. "o'brien" -> "O'Brien", "smith-jones" -> "Smith-Jones")
    var capitalizedName: String {
        let base = self.trimmed.lowercased()
        if base.isEmpty { return "" }
        
        let parts = base.split(separator: " ").map { part -> String in
            let p = String(part)
            if p.hasPrefix("o'"), p.count > 2 {
                let idx = p.index(p.startIndex, offsetBy: 2)
                let rest = p[idx...]
                return "O'" + rest.capitalized
            }
            return p.split(separator: "-").map { String($0).capitalized }.joined(separator: "-")
        }
        return parts.joined(separator: " ")
    }
}
