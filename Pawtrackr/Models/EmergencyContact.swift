//
//  EmergencyContact.swift
//  Pawtrackr
//

import Foundation
import SwiftData

@Model
final class EmergencyContact {
    var uuid: UUID
    var name: String
    var relation: String?
    var phone: String

    // Inverse relationship to Client
    var owner: Client?

    init(name: String, relation: String? = nil, phone: String) {
        self.uuid = UUID()
        self.name = name
        self.relation = relation
        self.phone = phone
    }
}

