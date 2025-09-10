//
//  PetGender.swift
//  Pawtrackr
//
//  Simple gender enum used by Pet and UI components.
//  Blue for male, pink for female in UI (color decisions live in views).
//
//  Created by mac on 8/14/25.
//  Updated by mac on 8/17/25.
//

import Foundation

public enum PetGender: String, CaseIterable, Codable, Identifiable {
    case male
    case female
    case unknown

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .male: return "Male"
        case .female: return "Female"
        case .unknown: return "Unknown"
        }
    }

    /// Optional SF Symbol for small badges (actual color chosen by the View layer)
    public var symbolName: String {
        switch self {
        case .male: return "m.circle.fill"
        case .female: return "f.circle.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }
}
