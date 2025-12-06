//
//  DesignSystem.swift
//  Pawtrackr
//
//  Created by mac on 8/14/25.
//

import SwiftUI

#if os(macOS)
import AppKit // Import AppKit for NSColor on macOS
#endif

// Access control alignment: keep DS internal so it can reference internal model types (PetGender, Species) without exposing them in a public API.
enum DS {
    // MARK: - Colors
    enum ColorToken {
        #if os(macOS)
        static let background = Color(nsColor: .windowBackgroundColor)
        static let surface    = Color(nsColor: .underPageBackgroundColor)
        #else
        static let background = Color(.systemGroupedBackground)
        static let surface    = Color(.secondarySystemBackground)
        #endif
        static let border     = Color.gray.opacity(0.15)
        static let shadow     = Color.black.opacity(0.08)

        // Accents
        // Tailwind-inspired palette
        static let primary    = Color(red: 99/255,  green: 102/255, blue: 241/255) // #6366F1
        static let success    = Color(red: 16/255,  green: 185/255, blue: 129/255) // #10B981
        static let warning    = Color(red: 245/255, green: 158/255, blue: 11/255)  // #F59E0B
        static let danger     = Color(red: 239/255, green: 68/255,  blue: 68/255)  // #EF4444
        static let info       = Color(red: 59/255,  green: 130/255, blue: 246/255) // #3B82F6

        static let genderMale = info
        static let genderFemale = Color(red: 236/255, green: 72/255, blue: 153/255) // #EC4899

        // Session (active visit) accent tokens
        static let session           = success                           // primary accent (rails, icons)
        static let sessionBackground = success.opacity(0.12)             // chips / soft fills
        static let sessionText       = success                           // text on the soft chip

        // Gender
        static func gender(_ g: PetGender) -> Color { g == .male ? genderMale : genderFemale }

        // Species (soft tints used behind paw/badges)
        static func species(_ s: Species) -> Color {
            switch s {
            case .dog: return .brown
            case .cat: return .orange
            }
        }

        /// Centralized tint used for species+gender badges (Client Center avatars).
        /// We bias the tint by gender for clarity, and keep it soft for backgrounds.
        static func avatarTint(species: Species, gender: PetGender) -> Color {
            let base = DS.ColorToken.gender(gender)
            switch species {
            case .dog, .cat: return base.opacity(0.22)
            }
        }

        /// Top-bar gradient for cards based on gender.
        static func genderGradient(_ gender: PetGender) -> LinearGradient {
            let c = DS.ColorToken.gender(gender)
            return LinearGradient(
                colors: [c.opacity(0.95), c.opacity(0.65)],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    // MARK: - Spacing
    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs:  CGFloat = 6
        static let sm:  CGFloat = 8
        static let md:  CGFloat = 12
        static let lg:  CGFloat = 16
        static let xl:  CGFloat = 20
        static let xxl: CGFloat = 24
    }

    // MARK: - Radii
    enum Radius {
        static let sm: CGFloat = 10
        static let md: CGFloat = 14
        static let lg: CGFloat = 18
        static let pill: CGFloat = 999
    }

    // MARK: - Rails
    enum Rail {
        static let width: CGFloat = 4
    }

    // MARK: - Shadows
    // This enum is removed because SwiftUI.ShadowStyle cannot be initialized directly.
    // Shadows are applied via the .shadow() modifier in components like Card.swift.

    // MARK: - Typography helpers
    enum TypeScale {
        static let title    = Font.title3.weight(.semibold)
        static let headline = Font.headline
        static let subhead  = Font.subheadline
        static let footnote = Font.footnote
        static let caption  = Font.caption
    }
}

// MARK: - Convenience modifiers
extension View {
    /// Gender-colored 3pt top bar for cards/screens.
    func genderAccentTopBar(_ gender: PetGender) -> some View {
        self.overlay(alignment: .top) {
            Rectangle().fill(DS.ColorToken.gender(gender)).frame(height: 3)
        }
    }

    /// Circular avatar ring with white stroke + gender ring.
    func avatarRings(gender: PetGender) -> some View {
        self
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .overlay(Circle().stroke(DS.ColorToken.gender(gender).opacity(0.9), lineWidth: 2))
    }

    /// Adds a left accent rail. Use with DS.ColorToken.session for active sessions.
    func leftAccentRail(_ color: Color) -> some View {
        overlay(alignment: .leading) {
            Rectangle()
                .fill(color)
                .frame(width: DS.Rail.width)
        }
    }

    /// Crisp 1px-equivalent border regardless of device scale.
    func hairlineBorder(_ color: Color, cornerRadius: CGFloat = DS.Radius.md) -> some View {
        #if os(iOS)
        let width = 1 / UIScreen.main.scale
        #elseif os(macOS)
        let width = 1 / (NSScreen.main?.backingScaleFactor ?? 2.0)
        #else
        let width: CGFloat = 1.0
        #endif
        return overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(color, lineWidth: width)
        )
    }

    /// Gender-colored gradient 3pt top bar.
    func genderAccentTopGradient(_ gender: PetGender) -> some View {
        overlay(alignment: .top) {
            Rectangle()
                .fill(DS.ColorToken.genderGradient(gender))
                .frame(height: 3)
        }
    }
}
