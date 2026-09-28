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
        case .ownerManager:
            return AppLocalization.localized("onboarding.role.owner.title", value: "Salon Owner / Manager")
        case .frontDeskGroomer:
            return AppLocalization.localized("onboarding.role.front_desk.title", value: "Front Desk / Groomer")
        }
    }

    var subtitle: String {
        switch self {
        case .ownerManager:
            return AppLocalization.localized(
                "onboarding.role.owner.subtitle",
                value: "Setup, pricing, reports, backups, and iCloud protection."
            )
        case .frontDeskGroomer:
            return AppLocalization.localized(
                "onboarding.role.front_desk.subtitle",
                value: "Check-in, check-out, safety notes, contacts, and active work."
            )
        }
    }
}
