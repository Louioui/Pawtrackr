//
//  iconSize.swift
//  Pawtrackr
//
//  Created by mac on 8/21/25.
//

import SwiftUI

/// Design-system tokens for common icon/avatar sizes used across the app.
/// Centralizes diameter, internal padding and default SF Symbol point size.
@frozen
public enum IconSizeToken: String, CaseIterable, Sendable {
    case xs  // tiny badges, status dots
    case sm  // tags, list rows
    case md  // primary avatars in lists
    case lg  // prominent tiles/cards
    case xl  // hero / detail headers

    /// The circular container diameter (points).
    public var diameter: CGFloat {
        switch self {
        case .xs: 20
        case .sm: 28
        case .md: 36
        case .lg: 48
        case .xl: 64
        }
    }

    /// Default SF Symbol or initials font size (points).
    /// Tuned to balance optical weight inside a circle at `diameter`.
    public var symbolPointSize: CGFloat {
        switch self {
        case .xs: 11
        case .sm: 14
        case .md: 18
        case .lg: 24
        case .xl: 32
        }
    }

    /// Optional internal content padding to keep glyphs off the edge.
    public var contentPadding: CGFloat {
        switch self {
        case .xs: 2
        case .sm: 3
        case .md: 4
        case .lg: 5
        case .xl: 6
        }
    }

    /// A subtle outline width appropriate for this size.
    public var strokeWidth: CGFloat { max(1, diameter * 0.06) }

    /// Corner radius to fully round a square with `diameter`.
    public var cornerRadius: CGFloat { diameter / 2 }
}

/// Helpers for scaling icon metrics for Dynamic Type.
/// Call from a View with `@Environment(\.sizeCategory) var sizeCategory` if needed.
public enum IconSizing {
    /// Returns a scaled symbol point size for a given token and content size category.
    public static func scaledSymbolPointSize(
        for token: IconSizeToken,
        sizeCategory: ContentSizeCategory
    ) -> CGFloat {
        let base = token.symbolPointSize
        // Conservative scaling so avatars don't explode with Large Text.
        let scale = scaleMultiplier(for: sizeCategory)
        return base * scale
    }

    /// Returns a scaled diameter while maintaining the same visual ratios.
    public static func scaledDiameter(
        for token: IconSizeToken,
        sizeCategory: ContentSizeCategory
    ) -> CGFloat {
        token.diameter * scaleMultiplier(for: sizeCategory)
    }

    /// A gently stepped multiplier tuned for circular icons.
    private static func scaleMultiplier(for category: ContentSizeCategory) -> CGFloat {
        switch category {
        case .extraSmall:                    0.90
        case .small:                         0.95
        case .medium:                        1.00
        case .large:                         1.05
        case .extraLarge:                    1.10
        case .extraExtraLarge:               1.15
        case .extraExtraExtraLarge:          1.20
        case .accessibilityMedium:           1.25
        case .accessibilityLarge:            1.30
        case .accessibilityExtraLarge:       1.35
        case .accessibilityExtraExtraLarge:  1.40
        case .accessibilityExtraExtraExtraLarge: 1.45
        @unknown default:                    1.0
        }
    }
}

#if DEBUG
#Preview("IconSize tokens") {
    VStack(spacing: 16) {
        ForEach(IconSizeToken.allCases, id: \.self) { token in
            HStack(spacing: 12) {
                Text(token.rawValue.uppercased())
                    .font(.caption)
                    .frame(width: 80, alignment: .trailing)

                Circle()
                    .strokeBorder(.gray.opacity(0.3), lineWidth: token.strokeWidth)
                    .frame(width: token.diameter, height: token.diameter)
                    .overlay {
                        Image(systemName: "pawprint.fill")
                            .font(.system(size: token.symbolPointSize, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
            }
        }
    }
    .padding()
}
#endif
