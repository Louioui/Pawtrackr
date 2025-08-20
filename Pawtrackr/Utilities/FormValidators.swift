//
//  FormValidators.swift
//  Pawtrackr
//
//  Created by mac on 8/15/25.
//

import Foundation

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
        out.firstName = try nonEmpty(input.firstName, fieldName: "First Name")
        out.lastName  = try nonEmpty(input.lastName,  fieldName: "Last Name")
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

    // MARK: - Money (USD)

    /// Parses a user-entered USD amount and returns a Decimal.
    /// Accepts inputs like "$45", "45", "45.00", "1,234.56", and "(45.00)" for negatives.
    static func usdAmount(_ value: String) throws -> Decimal {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ValidationError.custom(message: "Enter an amount.") }

        // 1) Try currency parser
        let currency = NumberFormatter()
        currency.numberStyle = .currency
        currency.locale = Locale(identifier: "en_US_POSIX")
        currency.currencyCode = "USD"
        currency.isLenient = true
        if let n = currency.number(from: trimmed) {
            return n.decimalValue
        }

        // 2) Try plain decimal (US)
        let decimal = NumberFormatter()
        decimal.numberStyle = .decimal
        decimal.locale = Locale(identifier: "en_US_POSIX")
        decimal.isLenient = true
        if let n = decimal.number(from: trimmed) {
            return n.decimalValue
        }

        // 3) Manual cleanup: strip currency, group separators, handle parentheses negatives
        var s = trimmed.replacingOccurrences(of: "\u{00A0}", with: " ")
        var negative = false
        if s.first == "(", s.last == ")" {
            negative = true
            s.removeFirst(); s.removeLast()
        }
        // Keep digits, dot, comma, dash
        let allowed = CharacterSet(charactersIn: "0123456789.,-")
        s = s.components(separatedBy: allowed.inverted).joined()
        // US: remove commas, use dot as decimal separator
        s = s.replacingOccurrences(of: ",", with: "")
        if negative { s = "-" + s }
        guard let dec = Decimal(string: s) else {
            throw ValidationError.custom(message: "Enter a valid USD amount.")
        }
        return dec
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
