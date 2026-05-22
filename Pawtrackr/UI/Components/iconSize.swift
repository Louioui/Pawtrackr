//
//  iconSize.swift
//  Pawtrackr
//
//  Created by mac on 8/21/25.
//

import SwiftUI

/// Design-system tokens for common icon/avatar sizes used across the app.
/// Centralizes diameter and symbol styling.
@frozen
public enum IconSizeToken: Equatable, Sendable, Hashable {
    case xs, sm, md, lg, xl, custom(CGFloat)

    public static var allCases: [IconSizeToken] = [.xs, .sm, .md, .lg, .xl]
    
    /// The circular container diameter (points).
    public var diameter: CGFloat {
        switch self {
        case .xs: return 24
        case .sm: return 32
        case .md: return 40
        case .lg: return 56
        case .xl: return 64
        case .custom(let v): return max(16, v)
        }
    }

    /// Relative glyph scale inside the circle. Tuned so small sizes look legible.
    public var iconScale: CGFloat {
        switch self {
        case .xs: return 0.46
        case .sm: return 0.44
        case .md: return 0.42
        case .lg: return 0.40
        case .xl: return 0.38
        case .custom(let v):
            let clamped = max(16, min(v, 80))
            let t = (clamped - 24) / (56 - 24)
            return max(0.36, min(0.50, 0.46 - t * 0.06))
        }
    }

    public var fontWeight: Font.Weight {
        diameter >= 56 ? .semibold : .medium
    }

    /// A subtle outline width appropriate for this size.
    public var strokeWidth: CGFloat { max(1, diameter * 0.06) }

    /// Corner radius to fully round a square with `diameter`.
    public var cornerRadius: CGFloat { diameter / 2 }
    
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .xs: hasher.combine(0)
        case .sm: hasher.combine(1)
        case .md: hasher.combine(2)
        case .lg: hasher.combine(3)
        case .xl: hasher.combine(4)
        case .custom(let value):
            hasher.combine(5)
            hasher.combine(value)
        }
    }
}

/// Helpers for scaling icon metrics for Dynamic Type.
public enum IconSizing {
    /// Returns a scaled diameter for a given token and content size category.
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
                Text(String(describing: token).uppercased())
                    .font(.caption)
                    .frame(width: 80, alignment: .trailing)

                Circle()
                    .strokeBorder(.gray.opacity(0.3), lineWidth: token.strokeWidth)
                    .frame(width: token.diameter, height: token.diameter)
                    .overlay {
                        Image(systemName: "pawprint.fill")
                            .font(.system(size: token.diameter * token.iconScale, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
            }
        }
    }
    .padding()
}
#endif
