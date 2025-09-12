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
        case "calm": return ("🧘", "Calm")
        case "cooperative": return ("🤝", "Cooperative")
        case "anxious": return ("😟", "Anxious")
        case "nervous": return ("😬", "Nervous")
        case "aggressive": return ("🛑", "Aggressive")
        case "senior": return ("🧓", "Senior")
        case "puppy", "puppy / young", "young": return ("🐶", "Puppy / Young")
        case "specialneeds", "special needs": return ("❤️‍🩹", "Special Needs")
        default:
            // Title-case fallback label
            let label = key.split(separator: " ").map { $0.capitalized }.joined(separator: " ")
            return (nil, label)
        }
    }
}

