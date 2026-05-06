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

    /// The payment amount (always non-negative and rounded to 2 decimal places).
    var amount: Decimal

    var method: Method
    var paidAt: Date
    var note: String?
    var externalReference: String?

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
    }

    // MARK: - Mutating API
    func setAmount(_ newAmount: Decimal) {
        amount = max(0, newAmount).roundedMoney()
    }
}

// MARK: - Payment Method Enum

extension Payment {
    enum Method: String, Codable, CaseIterable, Identifiable {
        case cash, debitCard, creditCard, zelle, other

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
    }
}
