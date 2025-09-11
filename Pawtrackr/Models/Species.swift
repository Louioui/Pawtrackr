//
//  Species.swift
//  Pawtrackr
//
//  Created by mac on 8/14/25.
//

// FIX: Added 'public' to match the access level of AvatarView.
public enum Species: String, CaseIterable, Codable, Identifiable {
    case dog
    case cat

    public var id: String { rawValue }

    public var displayName: String {
        rawValue.capitalized
    }

    public var iconName: String {
        switch self {
        case .dog: return "pawprint.fill"
        case .cat: return "pawprint"
        }
    }
}
