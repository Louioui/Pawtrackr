//
//  CheckoutTransaction.swift
//  Pawtrackr
//
//  Durable checkout audit/idempotency record.
//

import Foundation
import SwiftData

@Model
final class CheckoutTransaction {
    var uuid: UUID = UUID()
    var idempotencyKey: String = ""
    var visitUUID: UUID = UUID()
    var petUUID: UUID = UUID()
    var clientUUID: UUID?
    var amount: Decimal = Decimal.zero
    var methodRaw: String = Payment.Method.cash.rawValue
    var externalReference: String?
    var statusRaw: String = Status.processing.rawValue
    var attemptCount: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var completedAt: Date?
    var failureMessage: String?
    var deviceID: UUID = DeviceIdentity.currentID

    init(
        idempotencyKey: String,
        visitUUID: UUID,
        petUUID: UUID,
        clientUUID: UUID?,
        amount: Decimal,
        method: Payment.Method,
        externalReference: String?
    ) {
        self.uuid = UUID()
        self.idempotencyKey = idempotencyKey
        self.visitUUID = visitUUID
        self.petUUID = petUUID
        self.clientUUID = clientUUID
        self.amount = amount.roundedMoney()
        self.methodRaw = method.rawValue
        self.externalReference = externalReference
        self.statusRaw = Status.processing.rawValue
        self.attemptCount = 0
        self.createdAt = .now
        self.updatedAt = .now
        self.completedAt = nil
        self.failureMessage = nil
        self.deviceID = DeviceIdentity.currentID
    }

    var status: Status {
        get { Status(rawValue: statusRaw) ?? .processing }
        set { statusRaw = newValue.rawValue }
    }

    var method: Payment.Method {
        Payment.Method(rawValue: methodRaw) ?? .cash
    }

    func markProcessing(
        amount: Decimal,
        method: Payment.Method,
        externalReference: String?,
        clientUUID: UUID?
    ) {
        self.amount = amount.roundedMoney()
        self.methodRaw = method.rawValue
        self.externalReference = externalReference
        self.clientUUID = clientUUID
        self.status = .processing
        self.failureMessage = nil
        self.attemptCount += 1
        self.updatedAt = .now
        self.deviceID = DeviceIdentity.currentID
    }

    func markSucceeded(completedAt: Date) {
        self.status = .succeeded
        self.completedAt = completedAt
        self.failureMessage = nil
        self.updatedAt = .now
    }

    func markFailed(_ message: String) {
        self.status = .failed
        self.failureMessage = message
        self.updatedAt = .now
    }
}

extension CheckoutTransaction {
    enum Status: String, Codable, CaseIterable {
        case processing
        case succeeded
        case failed
    }
}
