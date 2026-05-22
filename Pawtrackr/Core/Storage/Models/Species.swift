//
//  Species.swift
//  Pawtrackr
//
//  Created by mac on 8/14/25.
//

import Foundation

// FIX: Added 'public' to match the access level of AvatarView.
public enum Species: String, CaseIterable, Codable, Identifiable, Sendable {
    case dog
    case cat

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .dog:
            return NSLocalizedString("species.dog", value: "Dog", comment: "")
        case .cat:
            return NSLocalizedString("species.cat", value: "Cat", comment: "")
        }
    }

    public var iconName: String {
        switch self {
        case .dog: return "pawprint.fill"
        case .cat: return "pawprint"
        }
    }
}
