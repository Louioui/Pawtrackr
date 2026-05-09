//
//  Payment.swift
//  Pawtrackr
//
//  Created by mac on 8/14/25.
//  Updated by Assistant on 2025-09-03.
//

import Foundation
import SwiftData

@Model
final class Payment {
    // MARK: - Properties
    // Non-optional properties have defaults for CloudKit compatibility.

    /// The payment amount (always non-negative and rounded to 2 decimal places).
    var amount: Decimal = Decimal.zero

    var method: Method = Payment.Method.cash
    var paidAt: Date = Date()
    var note: String?
    var externalReference: String?
    var lastModifiedBy: UUID = DeviceIdentity.currentID
    var lastModifiedAt: Date = Date()

    // MARK: - Relationships
    var visit: Visit?

    // MARK: - Init

    init(amount: Decimal,
         method: Method,
         paidAt: Date = .now,
         note: String? = nil,
         externalReference: String? = nil) {
        self.amount = max(0, amount).roundedMoney()
        self.method = method
        self.paidAt = paidAt
        self.note = note
        self.externalReference = externalReference
        self.lastModifiedBy = DeviceIdentity.currentID
        self.lastModifiedAt = .now
    }

    // MARK: - Mutating API
    func setAmount(_ newAmount: Decimal) {
        amount = max(0, newAmount).roundedMoney()
        markModified()
    }

    func markModified() {
        lastModifiedBy = DeviceIdentity.currentID
        lastModifiedAt = .now
    }
}

// MARK: - Payment Method Enum

extension Payment {
    enum Method: String, Codable, CaseIterable, Identifiable {
        case cash, debitCard, creditCard, zelle, other

        enum ReferenceFormat: Equatable {
            case none
            case cardLast4
            case transactionID
            case freeform
        }

        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .cash: return "Cash"
            case .debitCard: return "Debit"
            case .creditCard: return "Credit"
            case .zelle: return "Zelle"
            case .other: return "Other"
            }
        }

        var systemImage: String {
            switch self {
            case .cash: return "banknote"
            case .debitCard, .creditCard: return "creditcard"
            case .zelle: return "dollarsign.circle"
            case .other: return "questionmark.circle"
            }
        }

        var requiresExternalReference: Bool {
            switch self {
            case .debitCard, .creditCard, .zelle: return true
            case .cash, .other: return false
            }
        }

        var referenceFormat: ReferenceFormat {
            switch self {
            case .cash: return .none
            case .debitCard, .creditCard: return .cardLast4
            case .zelle: return .transactionID
            case .other: return .freeform
            }
        }

        var referenceFieldTitle: String {
            switch self {
            case .cash: return "Reference"
            case .debitCard, .creditCard: return "Last 4 Digits"
            case .zelle: return "Transaction ID"
            case .other: return "Reference"
            }
        }

        var referencePlaceholder: String {
            switch self {
            case .cash: return "Optional note"
            case .debitCard, .creditCard: return "1234"
            case .zelle: return "ZELLE-48291"
            case .other: return "Reference"
            }
        }

        var referenceHelperText: String {
            switch self {
            case .cash:
                return "You can leave this blank for cash payments."
            case .debitCard, .creditCard:
                return "Use the last 4 digits from the card or terminal slip."
            case .zelle:
                return "Use the confirmation or transfer ID from the payment."
            case .other:
                return "Add any note that will help you reconcile the payment later."
            }
        }

        func normalizeReference(_ value: String) -> String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

            switch referenceFormat {
            case .none, .freeform:
                return trimmed
            case .cardLast4:
                let digits = trimmed.filter(\.isNumber)
                return String(digits.suffix(4))
            case .transactionID:
                return trimmed.uppercased()
            }
        }

        func isValidReference(_ value: String) -> Bool {
            let normalized = normalizeReference(value)

            switch referenceFormat {
            case .none, .freeform:
                return true
            case .cardLast4:
                return normalized.count == 4
            case .transactionID:
                return !normalized.isEmpty
            }
        }

        func validationMessage(for value: String) -> String? {
            guard requiresExternalReference else { return nil }

            let normalized = normalizeReference(value)
            guard !normalized.isEmpty else {
                return "Enter \(referenceFieldTitle.lowercased()) to continue."
            }

            switch referenceFormat {
            case .cardLast4 where normalized.count < 4:
                return "Enter all 4 digits before continuing."
            default:
                return nil
            }
        }

        func preservesReference(whenSwitchingFrom previousMethod: Method) -> Bool {
            referenceFormat == previousMethod.referenceFormat && referenceFormat != .none
        }
    } 
}
