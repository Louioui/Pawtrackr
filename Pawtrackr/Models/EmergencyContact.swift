//
//  EmergencyContact.swift
//  Pawtrackr
//

import Foundation
import SwiftData

@Model
final class EmergencyContact {
    // Defaults for CloudKit compatibility.
    var uuid: UUID = UUID()
    var name: String = ""
    var relation: String?
    var phone: String = ""

    // Inverse relationship to Client
    var owner: Client?

    init(name: String, relation: String? = nil, phone: String) {
        self.uuid = UUID()
        self.name = name
        self.relation = relation
        self.phone = phone
    }
}

// Use a stable UUID-backed identity to avoid relying on persistentModelID in SwiftUI lists/alerts.
extension EmergencyContact: Identifiable {
    var id: UUID { uuid }
}
