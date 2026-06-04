import Foundation
import SwiftData

/// Background actor responsible for expensive calculations in the Checkout flow.
/// Keeps the main thread free for high-frequency UI interactions.
actor CheckoutCalculatorActor {
    
    func calculateTotal(items: [VisitItem]) -> Decimal {
        items.reduce(Decimal.zero) { $0 + $1.lineTotal }
    }
    
    func generateFingerprint(selectedServiceIDs: [PersistentIdentifier], selectedAddOnIDs: [PersistentIdentifier], allServices: [Service], addOnServices: [Service], sessionNotes: String, amountString: String, tipAmountString: String, selectedTipPercentage: Int?, selectedPaymentMethodRawValue: String, externalReference: String, tags: [String], hadBeforePhoto: Bool, hadAfterPhoto: Bool, visitUUID: String, petUUID: String, currentStepRawValue: Int) -> String {
        let serviceUUIDs = allServices
            .filter { selectedServiceIDs.contains($0.persistentModelID) }
            .map(\.uuid.uuidString).sorted().joined(separator: "|")
        let addOnUUIDs = addOnServices
            .filter { selectedAddOnIDs.contains($0.persistentModelID) }
            .map(\.uuid.uuidString).sorted().joined(separator: "|")
        let tagList = tags.sorted().joined(separator: "|")
        let parts: [String] = [
            visitUUID,
            petUUID,
            String(currentStepRawValue),
            sessionNotes,
            amountString,
            tipAmountString,
            String(selectedTipPercentage ?? 0),
            serviceUUIDs,
            addOnUUIDs,
            selectedPaymentMethodRawValue,
            externalReference,
            tagList,
            String(hadBeforePhoto),
            String(hadAfterPhoto)
        ]
        return parts.joined(separator: "||")
    }
}
