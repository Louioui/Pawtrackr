//
//  SpeciesAndGenderIcons.swift
//  Pawtrackr
//
//  Created by mac on 8/14/25.
//

import SwiftUI

/// Lightweight helper to render a small, rounded species badge with a gender ring.
/// Usage: SpeciesAndGenderIcons.badge(for: pet.species, gender: pet.gender, size: 28)
struct SpeciesAndGenderIcons {
    @ViewBuilder
    static func badge(for species: Species, gender: PetGender, size: CGFloat = 28) -> some View {
        ZStack {
            Circle()
                .fill(speciesColor(species).opacity(0.15))
                .frame(width: size, height: size)
            Image(systemName: {
                switch species {
                case .dog: return "dog.fill"
                case .cat: return "cat.fill"
                default: return "pawprint.fill"
                }
            }())
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(speciesColor(species))
        }
        .frame(width: size, height: size)
        .overlay(
            Circle().stroke(genderColor(gender).opacity(0.9), lineWidth: 2)
        )
        .accessibilityLabel(accessibilityLabel(for: species, gender: gender))
        .accessibilityHint("Species badge with gender color ring")
    }

    private static func speciesColor(_ s: Species) -> Color {
        switch s {
        case .dog: return Color.brown
        case .cat: return Color.orange
        default: return Color.gray
        }
    }

    private static func genderColor(_ g: PetGender) -> Color {
        // Corrected: The switch statement is now exhaustive
        switch g {
        case .male: return .blue
        case .female: return .pink
        case .unknown: return .gray
        }
    }

    private static func accessibilityLabel(for species: Species, gender: PetGender) -> Text {
        // Updated to use the gender's displayName property for consistency
        return Text("\(species.rawValue.capitalized), \(gender.displayName.lowercased())")
    }
}
