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
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch key {
        case "calm":
            return ("🧘", NSLocalizedString("pet.behavior.calm", value: "Calm", comment: ""))
        case "cooperative":
            return ("🤝", NSLocalizedString("pet.behavior.cooperative", value: "Cooperative", comment: ""))
        case "anxious":
            return ("😟", NSLocalizedString("pet.behavior.anxious", value: "Anxious", comment: ""))
        case "nervous":
            return ("😬", NSLocalizedString("pet.behavior.nervous", value: "Nervous", comment: ""))
        case "aggressive":
            return ("🛑", NSLocalizedString("pet.behavior.aggressive", value: "Aggressive", comment: ""))
        case "senior":
            return ("🧓", NSLocalizedString("pet.behavior.senior", value: "Senior", comment: ""))
        case "puppy", "puppy / young", "young":
            return ("🐶", NSLocalizedString("pet.behavior.puppy_young", value: "Puppy / Young", comment: ""))
        case "specialneeds", "special needs":
            return ("❤️‍🩹", NSLocalizedString("pet.behavior.special_needs", value: "Special Needs", comment: ""))
        default:
            // Title-case fallback label
            let label = key.split(separator: " ").map { $0.capitalized }.joined(separator: " ")
            return (nil, label)
        }
    }
}
