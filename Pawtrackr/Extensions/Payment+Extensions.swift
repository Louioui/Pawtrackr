//
//  Payment+Extensions.swift
//  Pawtrackr
//
//  Created by mac on 9/5/25.
//

import Foundation

extension Payment {
    // FIX: Mark properties that use @MainActor-isolated formatters as @MainActor.
    @MainActor
    var amountCurrencyString: String {
        amount.moneyString
    }

    var amountCents: Int {
        NSDecimalNumber(decimal: amount * 100).intValue
    }
    
    @MainActor
    var receiptSummary: String {
        var components: [String] = [
            amount.moneyString,
            method.displayName,
            paidAt.shortDateTime
        ]
        if let ref = externalReference?.trimmed, !ref.isEmpty { components.append("Ref: \(ref)") }
        if let note = note?.trimmed, !note.isEmpty { components.append(note) }
        
        return components.joined(separator: " • ")
    }
}
