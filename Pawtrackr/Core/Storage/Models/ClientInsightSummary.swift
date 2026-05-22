//
//  ClientInsightSummary.swift
//  Pawtrackr
//
//  Derived client metrics used to keep Insights fast on large stores.
//

import Foundation
import SwiftData

@Model
final class ClientInsightSummary {
    var clientUUID: UUID = UUID()
    var clientName: String = ""
    var totalSpent: Decimal = Decimal.zero
    var visitCount: Int = 0
    var isRecurring: Bool = false
    var isChurnRisk: Bool = false
    var lastVisitAt: Date?
    var updatedAt: Date = Date()

    init(
        clientUUID: UUID,
        clientName: String,
        totalSpent: Decimal,
        visitCount: Int,
        isChurnRisk: Bool,
        lastVisitAt: Date?
    ) {
        self.clientUUID = clientUUID
        self.clientName = clientName
        self.totalSpent = totalSpent.roundedMoney()
        self.visitCount = visitCount
        self.isRecurring = visitCount > 1
        self.isChurnRisk = isChurnRisk
        self.lastVisitAt = lastVisitAt
        self.updatedAt = .now
    }

    func update(
        clientName: String,
        totalSpent: Decimal,
        visitCount: Int,
        isChurnRisk: Bool,
        lastVisitAt: Date?
    ) {
        self.clientName = clientName
        self.totalSpent = totalSpent.roundedMoney()
        self.visitCount = visitCount
        self.isRecurring = visitCount > 1
        self.isChurnRisk = isChurnRisk
        self.lastVisitAt = lastVisitAt
        self.updatedAt = .now
    }
}
