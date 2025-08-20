//
//  IconCircle.swift
//  Pawtrackr
//
//  Reusable circular icon with configurable size and colors.
//  Useful for pet avatars when no photo is available, or small accent icons.
//
//  Created by mac on 8/14/25.
//  Updated by mac on 8/16/25.
//

import SwiftUI

struct IconCircle: View {
    enum Style {
        case solid(Color, Color)             // bg, foreground
        case tinted(Color)                   // bg with white icon
        case auto(species: Species?, gender: PetGender?) // blue for male, pink for female; neutral otherwise
    }

    private let systemImage: String
    private let size: CGFloat
    private let style: Style
    private let lineWidth: CGFloat

    init(systemImage: String,
                size: CGFloat = 40,
                style: Style = .tinted(.blue.opacity(0.15)),
                lineWidth: CGFloat = 0) {
        self.systemImage = systemImage
        self.size = size
        self.style = style
        self.lineWidth = lineWidth
    }

    var body: some View {
        let (bg, fg) = colors(for: style)
        ZStack {
            Circle()
                .fill(bg)
                .overlay(
                    Circle().strokeBorder(fg.opacity(lineWidth > 0 ? 0.25 : 0), lineWidth: lineWidth)
                )
            Image(systemName: systemImage)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(fg)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func colors(for style: Style) -> (Color, Color) {
        switch style {
        case let .solid(bg, fg):
            return (bg, fg)
        case let .tinted(bg):
            return (bg, .white)
        case let .auto(species: _, gender: gender):
            let tint = DS.ColorToken.gender(gender ?? .unknown)
            return (tint.opacity(0.15), tint)
        }
    }
}

// MARK: - Convenience for pets

extension IconCircle {
    /// Convenience init for pet placeholder icon (dog/cat), colored by gender.
    init(species: Species, gender: PetGender, size: CGFloat = 40) {
        let sys = (species == .cat) ? "pawprint.circle.fill" : "pawprint.fill"
        self.init(systemImage: sys, size: size, style: .auto(species: species, gender: gender))
    }
}

// MARK: - Preview

struct IconCircle_Previews: PreviewProvider {
    static var previews: some View {
        HStack(spacing: 16) {
            IconCircle(systemImage: "plus")
            IconCircle(systemImage: "scissors", style: .tinted(.purple.opacity(0.15)))
            IconCircle(systemImage: "pawprint.fill", style: .solid(.white, .blue))
            IconCircle(species: .dog, gender: .male)
            IconCircle(species: .cat, gender: .female)
        }
        .padding()
        #if os(macOS)
        .background(Color(nsColor: .windowBackgroundColor))
        #else
        .background(Color(.systemGroupedBackground))
        #endif
        .previewLayout(.sizeThatFits)
    }
}
