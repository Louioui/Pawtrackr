//
//  GradientTopLine.swift
//  Pawtrackr
//
//  Created by mac on 8/17/25.
//

import SwiftUI

#if os(iOS)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif

/// A thin, full‑width gradient line you can overlay at the top edge of any container (e.g. Card)
/// to provide a subtle accent (♂ blue / ♀ pink / neutral, etc).
///
/// Design goals:
/// - **No app model types in the API** (safe to keep `public`).
/// - Works with any `Color`, including tokens from your Design System (e.g., `DS.ColorToken.gender(...)`).
/// - Correct in light/dark mode and ignored by VoiceOver.
/// - Dead‑simple to compose: `Card { ... }.gradientTopLine(color: someColor)`.
public struct GradientTopLine: View {
    public let color: Color
    public let height: CGFloat

    /// - Parameters:
    ///   - color: Base color for the gradient (use DS tokens outside to avoid hardcoded colors).
    ///   - height: Height of the line in points. Defaults to `5`.
    public init(color: Color, height: CGFloat = 5) {
        self.color = color
        self.height = height
    }

    public var body: some View {
        // We intentionally leave corner rounding to the parent (e.g., Card clip),
        // so the strip seamlessly matches any container shape.
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        color.opacity(0.95),
                        color.opacity(0.80),
                        color.opacity(0.95)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: height)
            .accessibilityHidden(true)
            .accessibilityIdentifier("GradientTopLine")
    }
}

public extension View {
    /// Overlays a `GradientTopLine` aligned to the top edge.
    /// Use DS tokens to choose the color, e.g.:
    /// `someView.gradientTopLine(color: DS.ColorToken.gender(gender))`
    func gradientTopLine(color: Color, height: CGFloat = 5) -> some View {
        overlay(GradientTopLine(color: color, height: height), alignment: .top)
    }
}

#if DEBUG
struct GradientTopLine_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // iOS-style background
            #if os(iOS)
            demo
                .previewDisplayName("iOS Light/Dark")
                .environment(\.colorScheme, .light)

            demo
                .environment(\.colorScheme, .dark)
            #else
            // macOS-style background
            demo
                .previewDisplayName("macOS")
            #endif
        }
    }

    private static var demo: some View {
        VStack(spacing: 16) {
            sampleCard(title: "Male (Blue)")
                .gradientTopLine(color: .blue)

            sampleCard(title: "Female (Pink)")
                .gradientTopLine(color: .pink)

            sampleCard(title: "Neutral (Gray)")
                .gradientTopLine(color: .gray)
        }
        .padding()
        #if os(macOS)
        .background(Color(nsColor: .windowBackgroundColor))
        #else
        .background(Color(.systemGroupedBackground))
        #endif
    }

    private static func sampleCard(title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text("Top‑line accent demo").font(.subheadline)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
#if os(iOS)
                .fill(Color(UIColor.secondarySystemBackground))
#else
                .fill(Color(nsColor: .windowBackgroundColor))
#endif
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.black.opacity(0.06))
        )
    }
}
#endif
