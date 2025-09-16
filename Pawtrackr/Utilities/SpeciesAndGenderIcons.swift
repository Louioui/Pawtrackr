//
//  SpeciesAndGenderIcons.swift
//  Pawtrackr
//
//  Created by mac on 8/14/25.
//

import SwiftUI

/// Lightweight helper to render species/gender badges and avatar tints.
/// Unified with DesignSystem color tokens. Supports multiple styles.
struct SpeciesAndGenderIcons {

    /// Visual styles supported by the badge renderer.
    enum BadgeStyle {
        /// Simple filled background + glyph (no ring, no top bar)
        case plain
        /// Filled background + glyph + gender-colored ring
        case ringed
        /// Filled background + glyph + 3pt gender gradient bar at the top
        case topGradient
    }

    // MARK: - Public entry points

    /// Badge for a Pet model.
    @ViewBuilder
    static func badge(for pet: Pet,
                      size: CGFloat = 28,
                      style: BadgeStyle = .ringed,
                      isDecorative: Bool = false) -> some View {
        badge(for: pet.species, gender: pet.gender, size: size, style: style, isDecorative: isDecorative)
    }

    /// Badge for species + gender. Defaults to ringed style.
    @ViewBuilder
    static func badge(for species: Species,
                      gender: PetGender,
                      size: CGFloat = 28,
                      style: BadgeStyle = .ringed,
                      isDecorative: Bool = false) -> some View {
        let tint = avatarTint(for: species, gender: gender)
        let symbol = symbolName(for: species)

        // Base circle + glyph
        let base = ZStack {
            Circle()
                .fill(tint.fill)
            Image(systemName: symbol)
                .font(.system(size: max(12, size * 0.5), weight: .semibold))
                .foregroundStyle(tint.glyph)
                .accessibilityHidden(true)
        }
        .frame(width: size, height: size)

        let content: AnyView = {
            switch style {
            case .plain:
                return AnyView(base)

            case .ringed:
                return AnyView(
                    base.overlay(
                        Circle()
                            .stroke(tint.ring.opacity(0.9), lineWidth: ringWidth(for: size))
                    )
                )

            case .topGradient:
                return AnyView(
                    base
                        .genderAccentTopGradient(gender) // DS helper draws a 3pt gradient bar
                        .clipShape(Circle()) // ensure bar clips to the circle bounds
                )
            }
        }()

        content
            .accessibilityElement(children: .ignore)
            .modifier(_BadgeAX(label: accessibilityLabel(for: species, gender: gender), isDecorative: isDecorative))
    }

    // MARK: - Tints & tokens (single source of truth)

    /// Central source of truth for avatar tints used by IconCircle and other badges.
    /// Returns the fill (background), glyph (icon), and ring (gender) colors.
    static func avatarTint(for species: Species, gender: PetGender) -> (fill: Color, glyph: Color, ring: Color) {
        let sp = DS.ColorToken.species(species)
        let gn = DS.ColorToken.gender(gender)
        return (fill: sp.opacity(0.15), glyph: sp, ring: gn)
    }

    // MARK: - Internals

    private static func ringWidth(for size: CGFloat) -> CGFloat {
        // Scales gently with size while avoiding hairline on high-density screens.
        max(2, round(size * 0.07))
    }

    private static func symbolName(for species: Species) -> String {
        switch species {
        case .dog: return "dog.fill"
        case .cat: return "cat.fill"
        default:   return "pawprint.fill"
        }
    }

    private static func accessibilityLabel(for species: Species, gender: PetGender?) -> Text {
        if let gender {
            return Text("\(species.rawValue.capitalized), \(gender.displayName.lowercased())")
        } else {
            return Text("\(species.rawValue.capitalized)")
        }
    }

    fileprivate struct _BadgeAX: ViewModifier {
        let label: Text
        let isDecorative: Bool
        func body(content: Content) -> some View {
            if isDecorative {
                content.accessibilityHidden(true)
            } else {
                content.accessibilityLabel(label)
                    .accessibilityAddTraits(.isImage)
            }
        }
    }
}
