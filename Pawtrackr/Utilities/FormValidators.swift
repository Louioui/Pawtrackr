//
//  FormValidators.swift
//  Pawtrackr
//
//  Created by mac on 8/15/25.
//

import Foundation

// MARK: - Lightweight text utilities used by validators
private extension String {
    var trimmedAll: String { self.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Collapse runs of whitespace to a single space
    var collapsingWhitespace: String {
        self.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    /// Title‑cases a name while preserving inner punctuation (e.g., O'Neil, McDonald)
    func canonicalPersonName() -> String {
        let base = self.collapsingWhitespace.trimmedAll
        guard !base.isEmpty else { return base }
        return base
            .lowercased()
            .split(separator: " ")
            .map { word in
                var s = String(word).lowercased()
                // Handle common prefixes like Mc/Mac
                if s.hasPrefix("mc"), s.count > 2 {
                    let third = s.index(s.startIndex, offsetBy: 2)
                    // Capitalize 'M'
                    s.replaceSubrange(s.startIndex...s.startIndex, with: "M")
                    // Keep lowercase 'c'
                    s.replaceSubrange(s.index(after: s.startIndex)..<third, with: "c")
                    // Capitalize the next character
                    s.replaceSubrange(third...third, with: String(s[third]).uppercased())
                    return s
                }
                // Handle O' prefixes
                if s.hasPrefix("o'"), s.count > 2 {
                    let next = s.index(s.startIndex, offsetBy: 2)
                    // Capitalize 'O'
                    s.replaceSubrange(s.startIndex...s.startIndex, with: "O")
                    // Preserve the apostrophe
                    s.replaceSubrange(s.index(after: s.startIndex)..<next, with: "'")
                    // Capitalize the next character
                    s.replaceSubrange(next...next, with: String(s[next]).uppercased())
                    return s
                }
                // Default: title‑case first letter
                s.replaceSubrange(s.startIndex...s.startIndex, with: String(s[s.startIndex]).uppercased())
                return s
            }
            .joined(separator: " ")
    }
}

/// Reusable validators for Pawtrackr forms.
/// - Phone: US-only (all 50 states), normalized to E.164 (+1XXXXXXXXXX) via PhoneUtils (with strict local fallback).
/// - Money: USD-only parsing (en_US_POSIX).
/// - Email: optional; returns normalized (trimmed+lowercased) when valid.
enum FormValidators {

    // MARK: - Shared helpers

    /// Ensures a string is not empty (after trimming). Returns the trimmed value.
    @discardableResult
    static func nonEmpty(_ value: String, fieldName: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ValidationError.emptyField(fieldName: fieldName) }
        return trimmed
    }

    /// Basic optional email format check (US-agnostic). Allows empty (not required).
    /// Returns a normalized (trimmed, lowercased) email when valid; throws if non-empty and invalid.
    static func optionalEmail(_ value: String?) throws -> String? {
        guard let raw = value else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        let emailRegex = #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#
        let pred = NSPredicate(format: "SELF MATCHES[c] %@", emailRegex)
        guard pred.evaluate(with: trimmed) else {
            throw ValidationError.custom(message: "Please enter a valid email address.")
        }
        return trimmed.lowercased()
    }

    /// Validates and normalizes a US phone number (all 50 states) to E.164 (+1XXXXXXXXXX).
    /// Accepts 10 digits (assumes +1) or 11 with leading 1. Rejects non-NANP shapes.
    static func phone(_ value: String) throws -> String {
        let trimmed = try nonEmpty(value, fieldName: "Phone")
        // Prefer centralized utility (handles punctuation, spaces, NANP rules).
        if let e164 = PhoneUtils.toE164(trimmed) {
            return e164
        }
        // Strict local fallback (US-only) in case PhoneUtils is unavailable at call time.
        guard let e164 = toE164US(trimmed) else {
            throw ValidationError.invalidPhoneNumber
        }
        return e164
    }

    /// Formats an E.164 US phone number (e.g., "+15551234567") for display, e.g. "(555) 123-4567".
    /// Returns nil if input is not a valid E.164 +1 number.
    static func displayPhone(_ e164: String) -> String? {
        return PhoneUtils.display(e164)
    }

    // MARK: - Client form

    struct ClientFormInput {
        var firstName: String
        var lastName: String
        var phone: String
        var email: String?
        var address: String?
        init(firstName: String, lastName: String, phone: String, email: String? = nil, address: String? = nil) {
            self.firstName = firstName
            self.lastName = lastName
            self.phone = phone
            self.email = email
            self.address = address
        }
    }

    /// Validates a new client form. Returns a normalized copy (e.g., phone digits-only).
    static func validate(client input: ClientFormInput) throws -> ClientFormInput {
        var out = input
        out.firstName = try nonEmpty(input.firstName, fieldName: "First Name").canonicalPersonName()
        out.lastName  = try nonEmpty(input.lastName,  fieldName: "Last Name").canonicalPersonName()
        out.phone     = try phone(input.phone)
        out.email     = try optionalEmail(input.email)
        return out
    }

    // MARK: - Pet form

    struct PetFormInput {
        var name: String
        var breed: String?
        var color: String?
        var notes: String?
        init(name: String, breed: String? = nil, color: String? = nil, notes: String? = nil) {
            self.name = name
            self.breed = breed
            self.color = color
            self.notes = notes
        }
    }

    static func validate(pet input: PetFormInput) throws -> PetFormInput {
        var out = input
        out.name = try nonEmpty(input.name, fieldName: "Pet Name")
        return out
    }

    // MARK: - Behavior Tags
    /// Parses a comma-separated list of tags into a normalized, deduplicated array.
    static func parseBehaviorTagsCSV(_ value: String?) -> [String] {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let parts = value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { $0.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression) }
        var seen = Set<String>()
        var out: [String] = []
        for p in parts {
            let key = p.lowercased()
            if !seen.contains(key) { seen.insert(key); out.append(p) }
        }
        return out
    }

    // MARK: - Money (USD)

    /// Parses a user-entered USD amount and returns a Decimal.
    /// Accepts inputs like "$45", "45", "45.00", "1,234.56", and "(45.00)" for negatives.
    static func usdAmount(_ value: String) throws -> Decimal {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ValidationError.custom(message: "Enter an amount.") }

        // 1) Prefer centralized app parser for consistency
        if let dec = Formatters.parseCurrency(trimmed) {
            return dec.rounded(scale: 2)
        }

        // 2) Fallbacks (strict en_US_POSIX)
        let currency = NumberFormatter()
        currency.numberStyle = .currency
        currency.locale = Locale(identifier: "en_US_POSIX")
        currency.currencyCode = "USD"
        currency.isLenient = true
        if let n = currency.number(from: trimmed) { return n.decimalValue.rounded(scale: 2) }

        let decimal = NumberFormatter()
        decimal.numberStyle = .decimal
        decimal.locale = Locale(identifier: "en_US_POSIX")
        decimal.isLenient = true
        if let n = decimal.number(from: trimmed) { return n.decimalValue.rounded(scale: 2) }

        // 3) Manual cleanup as a last resort
        var s = trimmed.replacingOccurrences(of: "\u{00A0}", with: " ")
        var negative = false
        if s.first == "(", s.last == ")" { negative = true; s.removeFirst(); s.removeLast() }
        let allowed = CharacterSet(charactersIn: "0123456789.,-")
        s = s.components(separatedBy: allowed.inverted).joined()
        s = s.replacingOccurrences(of: ",", with: "")
        if negative { s = "-" + s }
        guard let dec = Decimal(string: s) else {
            throw ValidationError.custom(message: "Enter a valid USD amount.")
        }
        return dec.rounded(scale: 2)
    }

    /// Parses a tip string. Empty/whitespace returns 0. Uses same rules as `usdAmount`.
    static func tipAmount(_ value: String?) throws -> Decimal {
        guard let raw = value, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return 0 }
        return try usdAmount(raw)
    }

    // MARK: - Checkout validation
    struct CheckoutInput {
        var amountString: String
        var tipString: String?
    }
    struct CheckoutOutput { let amount: Decimal; let tip: Decimal }

    /// Validates checkout fields and returns normalized decimals (banker’s rounding to 2dp).
    static func validate(checkout input: CheckoutInput) throws -> CheckoutOutput {
        let amount = try usdAmount(input.amountString)
        let tip = try tipAmount(input.tipString)
        return CheckoutOutput(amount: amount, tip: tip)
    }

    // MARK: - Private helpers

    /// Converts a raw phone string to US E.164 if valid NANP: +1XXXXXXXXXX
    /// Rules: 10 digits (assume +1) or 11 starting with '1'; area & central office cannot start with 0/1.
    private static func toE164US(_ raw: String) -> String? {
        let digits = raw.filter { $0.isNumber }
        var d = digits
        if d.count == 11, d.first == "1" {
            d.removeFirst()
        }
        guard d.count == 10 else { return nil }
        // NANP basic shape checks
        let areaFirst = d[d.startIndex]
        let centralFirst = d[d.index(d.startIndex, offsetBy: 3)]
        guard ("2"..."9").contains(areaFirst), ("2"..."9").contains(centralFirst) else {
            return nil
        }
        return "+1" + d
    }

    // MARK: - PIN validation (for app lock)

    /// Validates a numeric PIN with a fixed length (default 4). Throws if invalid.
    static func pin(_ value: String, length: Int = 4) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == length, trimmed.allSatisfy({ $0.isNumber }) else {
            throw ValidationError.invalidPIN
        }
        return trimmed
    }
}

private extension Decimal {
    func rounded(scale: Int) -> Decimal {
        var result = Decimal()
        var value = self
        NSDecimalRound(&result, &value, scale, .bankers)
        return result
    }
}
