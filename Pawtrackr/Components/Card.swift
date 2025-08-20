//
//  Card.swift
//  Pawtrackr
//
//  Lightweight container with rounded corners and subtle shadow,
//  used across the app (history rows, visit details, etc.).
//
//  Created by mac on 8/14/25.
//  Updated by mac on 8/16/25.
//

import SwiftUI

#if os(iOS)
import UIKit
#endif

// Hairline width and platform separator color
fileprivate var _hairline: CGFloat {
#if os(iOS)
    return 1 / UIScreen.main.scale
#else
    return 1
#endif
}

fileprivate var _separatorColor: Color {
#if os(iOS)
    return Color(UIColor.separator).opacity(0.18)
#elseif os(macOS)
    return Color(nsColor: .separatorColor).opacity(0.18)
#else
    return Color.black.opacity(0.12)
#endif
}

public struct Card<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    private static var _defaultBackground: Color {
    #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
    #else
        Color(.systemBackground)
    #endif
    }

    private let cornerRadius: CGFloat
    private let padding: EdgeInsets
    private let background: Color
    private let onTap: (() -> Void)?
    @ViewBuilder private var content: () -> Content

    /// Create a standard card.
    /// - Parameters:
    ///   - cornerRadius: corner radius (default 16)
    ///   - padding: content padding (default 12 on all sides)
    ///   - background: background color (default .white)
    ///   - onTap: optional tap handler
    ///   - content: content builder
    public init(
        cornerRadius: CGFloat = 16,
        padding: EdgeInsets = EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12),
        background: Color? = nil,
        onTap: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.background = background ?? Self._defaultBackground
        self.onTap = onTap
        self.content = content
    }

    public var body: some View {
        Group {
            if let onTap {
                Button(action: onTap) { inner }
                    .buttonStyle(.plain)
            } else {
                inner
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var inner: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
                .padding(padding)
        }
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.06),
            radius: colorScheme == .dark ? 6 : 10,
            x: 0,
            y: colorScheme == .dark ? 2 : 6
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(_separatorColor, lineWidth: _hairline)
        )
    }
}

// MARK: - Convenience

public extension Card where Content == AnyView {
    /// A card that conditionally shows content.
    init?<T: View>(if condition: Bool,
                   cornerRadius: CGFloat = 16,
                   padding: EdgeInsets = EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12),
                   background: Color? = nil,
                   onTap: (() -> Void)? = nil,
                   @ViewBuilder content: @escaping () -> T) {
        guard condition else { return nil }
        self.init(cornerRadius: cornerRadius, padding: padding, background: background, onTap: onTap) {
            AnyView(content())
        }
    }
}

// MARK: - Style helpers

public extension View {
    /// Adds a 1‑px separator line to this view, aligned as specified (default: bottom).
    /// - Parameters:
    ///   - alignment: Where to place the separator (e.g., .bottom, .top).
    ///   - color: Optional custom color; defaults to the platform separator color.
    func cardSeparator(alignment: Alignment = .bottom, color: Color? = nil) -> some View {
        overlay(
            Rectangle()
                .fill(color ?? _separatorColor)
                .frame(height: _hairline),
            alignment: alignment
        )
    }
}

// MARK: - Preview

struct Card_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            VStack(spacing: 16) {
                Card {
                    Text("Simple Card")
                        .font(.headline)
                    Text("Secondary text")
                        .foregroundStyle(.secondary)
                }

                Card(onTap: { print("tapped") }) {
                    HStack {
                        Image(systemName: "pawprint.fill")
                        Text("Tappable Card")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding()
            // Use a macOS-compatible background color for the preview
#if os(macOS)
            .background(Color(nsColor: .windowBackgroundColor))
#else
            .background(Color(.systemGroupedBackground))
#endif
        }
    }
}
