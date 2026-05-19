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
    var updatedAt: Date = Date()
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
        self.updatedAt = .now
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
        updatedAt = .now
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
            case .cash:
                return NSLocalizedString("payment.method.cash", value: "Cash", comment: "")
            case .debitCard:
                return NSLocalizedString("payment.method.debit_card", value: "Debit", comment: "")
            case .creditCard:
                return NSLocalizedString("payment.method.credit_card", value: "Credit", comment: "")
            case .zelle:
                return NSLocalizedString("payment.method.zelle", value: "Zelle", comment: "")
            case .other:
                return NSLocalizedString("payment.method.other", value: "Other", comment: "")
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
            case .cash, .other:
                return NSLocalizedString("payment.reference.title", value: "Reference", comment: "")
            case .debitCard, .creditCard:
                return NSLocalizedString("payment.reference.last4", value: "Last 4 Digits", comment: "")
            case .zelle:
                return NSLocalizedString("payment.reference.transaction_id", value: "Transaction ID", comment: "")
            }
        }

        var referencePlaceholder: String {
            switch self {
            case .cash:
                return NSLocalizedString("payment.reference.placeholder_optional_note", value: "Optional note", comment: "")
            case .debitCard, .creditCard:
                return NSLocalizedString("payment.reference.placeholder_last4", value: "1234", comment: "")
            case .zelle:
                return NSLocalizedString("payment.reference.placeholder_transaction_id", value: "ZELLE-48291", comment: "")
            case .other:
                return NSLocalizedString("payment.reference.placeholder_reference", value: "Reference", comment: "")
            }
        }

        var referenceHelperText: String {
            switch self {
            case .cash:
                return NSLocalizedString("payment.reference.helper_cash", value: "You can leave this blank for cash payments.", comment: "")
            case .debitCard, .creditCard:
                return NSLocalizedString("payment.reference.helper_card", value: "Use the last 4 digits from the card or terminal slip.", comment: "")
            case .zelle:
                return NSLocalizedString("payment.reference.helper_zelle", value: "Use the confirmation or transfer ID from the payment.", comment: "")
            case .other:
                return NSLocalizedString("payment.reference.helper_other", value: "Add any note that will help you reconcile the payment later.", comment: "")
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
                return String(format: NSLocalizedString("payment.reference.validation.required_fmt", value: "Enter %@ to continue.", comment: ""), referenceFieldTitle.lowercased())
            }

            switch referenceFormat {
            case .cardLast4 where normalized.count < 4:
                return NSLocalizedString("payment.reference.validation.last4", value: "Enter all 4 digits before continuing.", comment: "")
            default:
                return nil
            }
        }

        func preservesReference(whenSwitchingFrom previousMethod: Method) -> Bool {
            referenceFormat == previousMethod.referenceFormat && referenceFormat != .none
        }
    } 
}
