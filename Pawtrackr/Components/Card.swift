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

/// Elevation presets for Card shadows (moved out of the generic `Card` type to avoid generic-nested-type lookup issues).
public enum CardElevation: Equatable {
    case flat
    case regular
    case raised
}

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

// Press feedback for tappable cards
fileprivate struct _ScaleOnPress: ButtonStyle {
    var scale: CGFloat = 0.98
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

public struct Card<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    #if os(macOS)
    @State private var _isHovered: Bool = false
    #endif

    // Stored styling properties (avoid name clashes with SwiftUI modifiers)
    private let _cornerRadius: CGFloat
    private let _contentPadding: EdgeInsets
    private let _backgroundColor: Color

    private let elevation: CardElevation
    private let showBorder: Bool
    private let hoverRaises: Bool
    private let onTap: (() -> Void)?
    private let accentTopLine: Color?
    private let accessibilityLabel: String?
    @ViewBuilder private var content: () -> Content

    // Default background per platform
    private static var _defaultBackground: Color {
        #if os(iOS)
        return Color(.systemBackground)
        #elseif os(macOS)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return Color.white
        #endif
    }

    /// Create a standard card.
    /// - Parameters:
    ///   - cornerRadius: corner radius (default 16)
    ///   - padding: content padding (default 12 on all sides)
    ///   - background: background color (default .white)
    ///   - elevation: elevation preset (default .regular)
    ///   - showBorder: whether to show border (default true)
    ///   - hoverRaises: whether hover raises shadow on macOS (default true)
    ///   - accentTopLine: optional accent color for top line (default nil)
    ///   - accessibilityLabel: optional accessibility label (default nil)
    ///   - onTap: optional tap handler
    ///   - content: content builder
    public init(
        cornerRadius: CGFloat = 16,
        padding: EdgeInsets = EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12),
        background: Color? = nil,
        elevation: CardElevation = .regular,
        showBorder: Bool = true,
        hoverRaises: Bool = true,
        accentTopLine: Color? = nil,
        accessibilityLabel: String? = nil,
        onTap: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self._cornerRadius = cornerRadius
        self._contentPadding = padding
        self._backgroundColor = (background ?? Self._defaultBackground)
        self.elevation = elevation
        self.showBorder = showBorder
        self.hoverRaises = hoverRaises
        self.accentTopLine = accentTopLine
        self.accessibilityLabel = accessibilityLabel
        self.onTap = onTap
        self.content = content
    }

    public var body: some View {
        Group {
            if let onTap {
                Button(action: onTap) { inner }
                    .buttonStyle(_ScaleOnPress())
                    .accessibilityAddTraits(.isButton)
            } else {
                inner
            }
        }
        .accessibilityLabel(accessibilityLabel ?? "")
        .accessibilityElement(children: .contain)
    }

    private var inner: some View {
        // Card body
        let shape = RoundedRectangle(cornerRadius: _cornerRadius, style: .continuous)
        return VStack(alignment: .leading, spacing: 0) {
            content()
                .padding(_contentPadding)
        }
        .background(_backgroundColor)
        .clipShape(shape)
        .contentShape(shape)
        .modifier(_ShadowModifier(colorScheme: colorScheme,
                                  elevation: elevation,
                                  hovered: hoveredIfEnabled))
        .overlay(
            ZStack(alignment: .top) {
                if showBorder {
                    shape.strokeBorder(_separatorColor, lineWidth: _hairline)
                }
                if let accentTopLine {
                    Rectangle()
                        .fill(accentTopLine)
                        .frame(height: max(2, _hairline * 3))
                        .clipShape(RoundedRectangle(cornerRadius: max(0, _cornerRadius - 1), style: .continuous))
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            }
        )
        #if os(macOS)
        .onHover { hovering in
            if hoverRaises { _isHovered = hovering }
        }
        #endif
    }

    private var hoveredIfEnabled: Bool {
        #if os(macOS)
        return hoverRaises && _isHovered
        #else
        return false
        #endif
    }
}

fileprivate extension CardElevation {
    func shadow(for colorScheme: ColorScheme, hovered: Bool) -> (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) {
        let isDark = (colorScheme == .dark)
        let base: (opacity: Double, radius: CGFloat, y: CGFloat) = {
            switch self {
            case .flat:    return (isDark ? 0.25 : 0.0, 0, 0)
            case .regular: return (isDark ? 0.35 : 0.06, isDark ? 6 : 10, isDark ? 2 : 6)
            case .raised:  return (isDark ? 0.45 : 0.12, isDark ? 10 : 16, isDark ? 4 : 10)
            }
        }()
        let hoverBoost: CGFloat = hovered ? 2 : 0
        let radius = max(0, base.radius + hoverBoost)
        let y = base.y + (hovered ? 1 : 0)
        return (Color.black.opacity(base.opacity), radius, 0, y)
    }
}

fileprivate struct _ShadowModifier: ViewModifier {
    var colorScheme: ColorScheme
    var elevation: CardElevation
    var hovered: Bool
    func body(content: Content) -> some View {
        let s = elevation.shadow(for: colorScheme, hovered: hovered)
        return content.shadow(color: s.color, radius: s.radius, x: s.x, y: s.y)
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
        self.init(cornerRadius: cornerRadius,
                  padding: padding,
                  background: background,
                  elevation: .regular,
                  showBorder: true,
                  hoverRaises: true,
                  onTap: onTap) {
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
                Card(accentTopLine: .blue) {
                    Text("Simple Card")
                        .font(.headline)
                    Text("Secondary text")
                        .foregroundStyle(.secondary)
                }

                Card(elevation: .raised, accentTopLine: .pink, accessibilityLabel: "Tappable Card", onTap: { print("tapped") }) {
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

#if DEBUG
extension CardElevation: CustomStringConvertible {
    public var description: String {
        switch self {
        case .flat: return "flat"
        case .regular: return "regular"
        case .raised: return "raised"
        }
    }
}
#endif
