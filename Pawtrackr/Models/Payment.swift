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
    
    var amount: Decimal {
        didSet {
            // Enforce that the amount is always non-negative and correctly rounded.
            let clamped = max(0, amount)
            let rounded = clamped.roundedMoney()
            if amount != rounded {
                amount = rounded
            }
        }
    }
    
    var method: Method
    @Attribute var paidAt: Date
    var note: String?
    @Attribute var externalReference: String?

    // MARK: - Relationships
    
    // FIX: The inverse side of a relationship is a plain property, with NO @Relationship macro.
    var visit: Visit?

    // MARK: - Init
    
    init(amount: Decimal,
         method: Method,
         paidAt: Date = .now,
         note: String? = nil,
         externalReference: String? = nil) {
        self.amount = amount
        self.method = method
        self.paidAt = paidAt
        self.note = note
        self.externalReference = externalReference
    }
}

// MARK: - Payment Method Enum

extension Payment {
    enum Method: String, Codable, CaseIterable, Identifiable {
        case cash, debitCard, creditCard, zelle, other

        // ... (Codable implementation is correct) ...

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
