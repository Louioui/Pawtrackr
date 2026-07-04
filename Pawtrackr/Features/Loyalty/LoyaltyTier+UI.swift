//
//  LoyaltyTier+UI.swift
//  Pawtrackr
//
//  Presentation styling for the loyalty tier ladder. Kept out of
//  LoyaltyTier.swift so the domain enum stays SwiftUI-free.
//

import SwiftUI

extension LoyaltyTier {
    var tint: Color {
        switch self {
        case .bronze: Color(red: 0.66, green: 0.44, blue: 0.25)
        case .silver: Color(red: 0.52, green: 0.56, blue: 0.62)
        case .gold: DS.ColorToken.warning
        case .platinum: Color.indigo
        }
    }

    var systemImage: String {
        switch self {
        case .bronze: "pawprint.fill"
        case .silver: "star.fill"
        case .gold: "crown.fill"
        case .platinum: "sparkles"
        }
    }
}
