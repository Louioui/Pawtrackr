//
//  CheckoutDraft.swift
//  Pawtrackr
//

import Foundation

struct CheckoutDraft: Codable, Equatable, Sendable {
    var visitID: UUID
    var petID: UUID
    var updatedAt: Date
    var currentStepRawValue: Int
    var sessionNotes: String
    var amountString: String
    var selectedServiceUUIDs: [UUID]
    var selectedAddOnUUIDs: [UUID]
    var selectedPaymentMethodRawValue: String
    var beforePhotoData: Data?
    var afterPhotoData: Data?
    var externalReference: String
    var tags: [String]

    init(
        visitID: UUID,
        petID: UUID,
        updatedAt: Date = .now,
        currentStepRawValue: Int,
        sessionNotes: String,
        amountString: String,
        selectedServiceUUIDs: [UUID],
        selectedAddOnUUIDs: [UUID],
        selectedPaymentMethodRawValue: String,
        beforePhotoData: Data?,
        afterPhotoData: Data?,
        externalReference: String,
        tags: [String]
    ) {
        self.visitID = visitID
        self.petID = petID
        self.updatedAt = updatedAt
        self.currentStepRawValue = currentStepRawValue
        self.sessionNotes = sessionNotes
        self.amountString = amountString
        self.selectedServiceUUIDs = selectedServiceUUIDs
        self.selectedAddOnUUIDs = selectedAddOnUUIDs
        self.selectedPaymentMethodRawValue = selectedPaymentMethodRawValue
        self.beforePhotoData = beforePhotoData
        self.afterPhotoData = afterPhotoData
        self.externalReference = externalReference
        self.tags = tags
    }
}
