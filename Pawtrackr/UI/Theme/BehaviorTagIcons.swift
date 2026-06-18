//
//  BehaviorTagIcons.swift
//  Pawtrackr
//
//  Utility to map pet behavior tags to a short label with an emoji for display.
//

import Foundation

enum BehaviorTagIcons {
    /// Map a raw tag string to a display tuple (emoji, label).
    /// Falls back to just the label when unknown.
    static func display(for raw: String) -> (emoji: String?, label: String) {
        if let kind = Pet.behaviorTagKind(for: raw) {
            switch kind {
            case .calm:
                return ("🧘", Pet.BehaviorTag.calm.displayName)
            case .cooperative:
                return ("🤝", Pet.BehaviorTag.cooperative.displayName)
            case .anxious:
                return ("😟", Pet.BehaviorTag.anxious.displayName)
            case .nervous:
                return ("😬", Pet.BehaviorTag.nervous.displayName)
            case .aggressive:
                return ("🛑", Pet.BehaviorTag.aggressive.displayName)
            case .specialNeeds:
                return ("❤️‍🩹", Pet.BehaviorTag.specialNeeds.displayName)
            }
        }

        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch key {
        case "senior":
            return ("🧓", NSLocalizedString("pet.behavior.senior", value: "Senior", comment: ""))
        case "puppy", "puppy / young", "young":
            return ("🐶", NSLocalizedString("pet.behavior.puppy_young", value: "Puppy / Young", comment: ""))
        default:
            // Title-case fallback label
            let label = key.split(separator: " ").map { $0.capitalized }.joined(separator: " ")
            return (nil, label)
        }
    }
}
