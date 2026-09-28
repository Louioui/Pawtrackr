//
//  OnboardingRole.swift
//  Pawtrackr
//

import Foundation

enum OnboardingRole: String, CaseIterable, Identifiable, Codable, Sendable {
    case ownerManager
    case frontDeskGroomer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ownerManager: return "Salon Owner / Manager"
        case .frontDeskGroomer: return "Front Desk / Groomer"
        }
    }

    var subtitle: String {
        switch self {
        case .ownerManager:
            return "Setup, pricing, reports, backups, and iCloud protection."
        case .frontDeskGroomer:
            return "Check-in, check-out, safety notes, contacts, and active work."
        }
    }
}
