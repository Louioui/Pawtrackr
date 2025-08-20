//
//  Species.swift
//  Pawtrackr
//
//  Created by mac on 8/14/25.
//



enum Species: String, CaseIterable, Codable, Identifiable {
    case dog
    case cat
    case bird
    case reptile
    case other

    var id: String { rawValue }

    var displayName: String {
        rawValue.capitalized
    }

    var iconName: String {
        switch self {
        case .dog:
            return "pawprint.fill"
        case .cat:
            return "pawprint"
        case .bird:
            return "bird"
        case .reptile:
            return "tortoise"
        case .other:
            return "questionmark.circle"
        }
    }
}
