//
//  Payment.swift
//  Pawtrackr
//
//  SwiftData model for a payment associated with a Visit.
//  Supports common methods (Cash, Debit, Zelle) and an optional note/reference.
//
//  Created by mac on 8/14/25.
//  Updated by mac on 8/17/25.
//

import Foundation
import SwiftData

@Model
final class Payment {
    enum Method: String, Codable, CaseIterable, Identifiable {
        case cash
        case debitCard
        case zelle
        case other
        var id: String { rawValue }
    }

    // MARK: - Core
    var amount: Decimal
    var method: Method
    var paidAt: Date
    var note: String?
    var externalReference: String? // e.g., Zelle txn id, last4, receipt no.

    // MARK: - Relations
    // Inverse relation: a Visit may own a Payment
    @Relationship(inverse: \Visit.payment) var visit: Visit?

    // MARK: - Init
    init(amount: Decimal, method: Method, visit: Visit? = nil, paidAt: Date = Date(), note: String? = nil, externalReference: String? = nil) {
        self.amount = amount
        self.method = method
        self.paidAt = paidAt
        self.note = note
        self.externalReference = externalReference
        self.visit = visit
    }
}

// MARK: - Convenience

extension Payment.Method {
    var displayName: String {
        switch self {
        case .cash: return "Cash"
        case .debitCard: return "Debit"
        case .zelle: return "Zelle"
        case .other: return "Other"
        }
    }

    // Add this computed property for the icon
    var systemImage: String {
        switch self {
        case .cash: return "banknote"
        case .debitCard: return "creditcard"
        case .zelle: return "dollarsign.circle"
        case .other: return "creditcard"
        }
    }
}
