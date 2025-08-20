//
//  PhoneUtils.swift
//  Pawtrackr
//
//  Created by mac on 8/14/25.
//  Upgraded by assistant on 8/17/25
//

import Foundation

/// Utility methods for working with United States (NANP) phone numbers.
/// - Scope: US only (+1); supports all 50 states and NANP rules.
/// - Storage: Save as E.164 "+1##########"
/// - UI: Show as "(AAA) BBB-CCCC" with optional " xEXT"
public enum PhoneUtils {

    // MARK: - Vanity letters → digits (NANP keypad)
    private static let vanityMap: [Character: Character] = [
        "A":"2","B":"2","C":"2",
        "D":"3","E":"3","F":"3",
        "G":"4","H":"4","I":"4",
        "J":"5","K":"5","L":"5",
        "M":"6","N":"6","O":"6",
        "P":"7","Q":"7","R":"7","S":"7",
        "T":"8","U":"8","V":"8",
        "W":"9","X":"9","Y":"9","Z":"9"
    ]

    // MARK: - Public API (backwards compatible)

    /// Normalize by mapping vanity letters to digits and stripping *all* non-digits.
    /// (Back-compat with previous implementation which returned digits-only.)
    public static func normalize(_ input: String) -> String {
        let mapped: [Character] = input.uppercased().map { vanityMap[$0] ?? $0 }
        let only = mapped.filter { $0.isNumber }
        return String(only)
    }

    /// Basic plausibility check for a US number.
    /// Accepts 10 digits, or 11 digits starting with "1".
    /// Enforces NANP "NXX NXX XXXX" (area & exchange cannot start with 0 or 1).
    public static func isValidUS(_ input: String) -> Bool {
        let (main, _) = splitExtension(input)
        let raw = normalize(main) // digits only
        // Accept 10 digits or 11 with leading country code "1"
        let digits: String
        if raw.count == 11, raw.first == "1" {
            digits = String(raw.dropFirst())
        } else if raw.count == 10 {
            digits = raw
        } else {
            return false
        }
        // Reject numbers where all digits are identical (e.g., 2222222222)
        if Set(digits).count == 1 { return false }
        // Area code and exchange (NXX NXX XXXX)
        let area = String(digits.prefix(3))
        let exchange = String(digits.dropFirst(3).prefix(3))
        // Disallow N11 service codes (211, 311, ..., 911) in area or exchange
        if area.hasSuffix("11") || exchange.hasSuffix("11") { return false }
        // Enforce NANP: area [2-9]XX, exchange [2-9]XX
        let pattern = "^[2-9]\\d{2}[2-9]\\d{6}$"
        guard let rx = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(location: 0, length: digits.utf16.count)
        return rx.firstMatch(in: digits, range: range) != nil
    }

    /// Backwards-compatible alias.
    public static func isValid(_ input: String) -> Bool { isValidUS(input) }

    /// Convert any user-entered US number into E.164 "+1##########".
    /// Returns nil if invalid. (Extension, if present, is ignored for storage.)
    public static func toE164(_ input: String) -> String? {
        guard let ten = tenDigits(input) else { return nil }
        return "+1" + ten
    }

    /// Pretty-print as "(AAA) BBB-CCCC" with optional " xEXT".
    /// Returns nil if the number isn't a valid US number.
    public static func display(_ input: String, includeExtension: Bool = true) -> String? {
        let (main, ext) = splitExtension(input)
        // If input is already E.164, main may still contain "+1"; handle smoothly.
        let base = main.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = base.hasPrefix("+1") ? base : main
        guard let ten = tenDigits(source) else { return nil }
        let area = ten.prefix(3)
        let mid = ten.dropFirst(3).prefix(3)
        let last = ten.suffix(4)
        var out = "(\(area)) \(mid)-\(last)"
        if includeExtension, let ext, !ext.isEmpty {
            out += " x\(ext)"
        }
        return out
    }

    /// Format a partially-entered US number as the user types.
    /// - Returns: "(AAA) BBB-CCCC" as digits accumulate. If >10 digits are typed, the extras are rendered as " xEXT".
    public static func formatAsYouType(_ input: String) -> String {
        let (main, ext) = splitExtension(input)
        let digits = normalize(main)
        let count = digits.count
        if count == 0 { return "" }
        if count <= 3 {
            return digits
        } else if count <= 6 {
            let area = digits.prefix(3)
            let mid = digits.dropFirst(3)
            var out = "(\(area)) \(mid)"
            if let ext, !ext.isEmpty { out += " x\(ext)" }
            return out
        } else {
            let area = digits.prefix(3)
            let mid = digits.dropFirst(3).prefix(3)
            let last = digits.dropFirst(6)
            var out = "(\(area)) \(mid)"
            if !last.isEmpty {
                out += "-\(last.prefix(4))"
            }
            // if user typed more than 10 digits, treat remainder as extension
            let remainder = digits.dropFirst(10)
            if remainder.count > 0 {
                out += " x\(remainder)"
            } else if let ext, !ext.isEmpty {
                out += " x\(ext)"
            }
            return out
        }
    }

    /// Masked display keeping only the last 4 digits visible: "(AAA) BBB-••••"
    public static func displayMasked(_ input: String) -> String? {
        guard let shown = display(input, includeExtension: false) else { return nil }
        if let r = shown.range(of: #"(\d{4})$"#, options: .regularExpression) {
            return shown.replacingCharacters(in: r, with: "••••")
        }
        return shown
    }

    /// Returns 10-digit search key if valid (digits only), otherwise nil.
    public static func searchKey(_ input: String) -> String? {
        return tenDigits(input)
    }

    /// If valid, split into (area, exchange, line) components.
    public static func splitComponents(_ input: String) -> (area: String, exchange: String, line: String)? {
        guard let ten = tenDigits(input) else { return nil }
        let area = String(ten.prefix(3))
        let exchange = String(ten.dropFirst(3).prefix(3))
        let line = String(ten.suffix(4))
        return (area, exchange, line)
    }

    /// Extract 10-digit national number (if valid).
    public static func tenDigits(_ input: String) -> String? {
        let (main, _) = splitExtension(input)
        let raw = normalize(main)
        // Accept already-normalized E.164 "+1##########"
        if input.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("+1"), raw.count == 11, raw.first == "1" {
            let ten = String(raw.dropFirst())
            return isValidUS(ten) ? ten : nil
        }
        let digits: String
        if raw.count == 11, raw.first == "1" {
            digits = String(raw.dropFirst())
        } else if raw.count == 10 {
            digits = raw
        } else {
            return nil
        }
        return isValidUS(digits) ? digits : nil
    }

    /// Check if a string is a valid US E.164 number: "+1" followed by 10 valid NANP digits.
    public static func isValidUSE164(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("+1") else { return false }
        // Strip everything but digits and ensure we have 11 with leading 1
        let raw = normalize(trimmed)
        guard raw.count == 11, raw.first == "1" else { return false }
        let ten = String(raw.dropFirst())
        return isValidUS(ten)
    }

    /// Try to coerce any US input (digits, formatted, or E.164) to canonical E.164.
    public static func toE164US(_ input: String) -> String? {
        if isValidUSE164(input) { return "+1" + (tenDigits(input) ?? "") }
        guard let ten = tenDigits(input) else { return nil }
        return "+1" + ten
    }

    /// Build a tel: URL string from any US input. Example: "tel:+11234567890". Returns nil if invalid.
    public static func telURLString(_ input: String) -> String? {
        guard let e164 = toE164US(input) else { return nil }
        return "tel:" + e164
    }

    /// Build an sms: URL. Example: "sms:+11234567890?&amp;body=Hello" (body is percent-encoded).
    public static func smsURLString(_ input: String, body: String? = nil) -> String? {
        guard let e164 = toE164US(input) else { return nil }
        guard let body, !body.isEmpty else {
            return "sms:" + e164
        }
        let allowed = CharacterSet.urlQueryAllowed
        let encoded = body.addingPercentEncoding(withAllowedCharacters: allowed) ?? body
        return "sms:" + e164 + "?&amp;body=" + encoded
    }

    // MARK: - Extension parsing

    /// Separate common extension notations like "x123", "ext. 4567", " #7890".
    /// Returns (main, ext) where `ext` is digits-only or nil.
    public static func splitExtension(_ input: String) -> (main: String, ext: String?) {
        let lower = input.lowercased()
        // Matches: x123, ext 4567, ext.456, extension 999, #1234 at end of string
        let pattern = "\\s*(x|ext\\.?|extension|#)\\s*(\\d{1,10})\\s*$"
        guard let rx = try? NSRegularExpression(pattern: pattern) else {
            return (input.trimmingCharacters(in: .whitespacesAndNewlines), nil)
        }
        let fullRange = NSRange(lower.startIndex..<lower.endIndex, in: lower)
        if let m = rx.firstMatch(in: lower, range: fullRange),
           m.numberOfRanges >= 3,
           let extRange = Range(m.range(at: 2), in: lower),
           let whole = Range(m.range(at: 0), in: lower) {
            let ext = String(lower[extRange]).filter { $0.isNumber }
            let main = input.replacingCharacters(in: whole, with: "")
            return (main.trimmingCharacters(in: .whitespacesAndNewlines), ext.isEmpty ? nil : ext)
        }
        return (input.trimmingCharacters(in: .whitespacesAndNewlines), nil)
    }

    #if DEBUG
    /// Handy examples for manual verification in unit tests or previews.
    public static let _examples: [String] = [
        "5551234567",
        "(415) 555-2671",
        "+1 (212) 555-1188",
        "702-555-0000 x1234",
        "1-310-555-0119",
        "800 FLOWERS"
    ]
    #endif
}
