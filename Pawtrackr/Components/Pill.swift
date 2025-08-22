//
//  Pill.swift
//  Pawtrackr
//
//  Lightweight chip/pill used for services, tags, and summary counts.
//
//  Created by mac on 8/14/25.
//  Updated by mac on 8/20/25 – enhanced sizes, semantics, and accessibility.
//

import SwiftUI

public struct Pill: View {
    // MARK: - Variants & Sizes
    public enum Style: Equatable {
        case filled(tint: Color = Color(.secondarySystemFill), text: Color = .primary)
        case outline(tint: Color = Color.gray.opacity(0.25), text: Color = .primary)
        case prominent(tint: Color, text: Color = .white)
    }

    public enum Size: CaseIterable {
        case xs, sm, md, lg

        var paddings: (horizontal: CGFloat, vertical: CGFloat) {
            switch self {
            case .xs: return (8, 4)
            case .sm: return (10, 6)
            case .md: return (12, 7)
            case .lg: return (14, 8)
            }
        }

        var font: Font {
            switch self {
            case .xs: return .caption2
            case .sm: return .caption
            case .md: return .callout
            case .lg: return .subheadline
            }
        }
    }

    /// Common semantic presets for quick, consistent usage across the app.
    public enum Semantic {
        case info
        case success
        case warning
        case danger
        case genderMale
        case genderFemale
        case neutral

        fileprivate func style(for appearance: Appearance) -> Style {
            switch self {
            case .info:
                return .filled(tint: appearance.infoBg, text: appearance.infoFg)
            case .success:
                return .filled(tint: appearance.successBg, text: appearance.successFg)
            case .warning:
                return .filled(tint: appearance.warningBg, text: appearance.warningFg)
            case .danger:
                return .filled(tint: appearance.dangerBg, text: appearance.dangerFg)
            case .genderMale:
                return .filled(tint: appearance.maleBg, text: appearance.maleFg)
            case .genderFemale:
                return .filled(tint: appearance.femaleBg, text: appearance.femaleFg)
            case .neutral:
                return .filled(tint: appearance.neutralBg, text: appearance.neutralFg)
            }
        }
    }

    // MARK: - Appearance Tokens
    /// Centralizes colors so they adapt to light/dark and are consistent across the app.
    struct Appearance {
        let infoBg: Color = Color.blue.opacity(0.12)
        let infoFg: Color = Color.blue
        let successBg: Color = Color.green.opacity(0.12)
        let successFg: Color = Color.green
        let warningBg: Color = Color.yellow.opacity(0.16)
        let warningFg: Color = Color.yellow.darkerIfNeeded()
        let dangerBg: Color = Color.red.opacity(0.12)
        let dangerFg: Color = Color.red
        let maleBg: Color = Color.blue.opacity(0.12)
        let maleFg: Color = Color.blue
        let femaleBg: Color = Color.pink.opacity(0.14)
        let femaleFg: Color = Color.pink
        let neutralBg: Color = Color.gray.opacity(0.12)
        let neutralFg: Color = Color.primary

        let outlineStrokeLight: Color = Color.gray.opacity(0.28)
        let outlineStrokeDark: Color = Color.white.opacity(0.22)
    }

    @Environment(\.colorScheme) private var colorScheme
    private let text: String
    private let systemImage: String?
    private let style: Style
    private let size: Size

    // Back-compat custom paddings/font (still supported via init below)
    private let customHorizontal: CGFloat?
    private let customVertical: CGFloat?
    private let customFont: Font?

    // Optional tap action to give the pill button semantics when desired
    private let onTap: (() -> Void)?

    // MARK: - Inits
    public init(text: String,
                systemImage: String? = nil,
                style: Style = .filled(),
                size: Size = .sm,
                horizontal: CGFloat? = nil,
                vertical: CGFloat? = nil,
                font: Font? = nil,
                onTap: (() -> Void)? = nil) {
        self.text = text
        self.systemImage = systemImage
        self.style = style
        self.size = size
        self.customHorizontal = horizontal
        self.customVertical = vertical
        self.customFont = font
        self.onTap = onTap
    }

    /// Semantic convenience init
    public init(_ text: String,
                systemImage: String? = nil,
                semantic: Semantic,
                size: Size = .sm,
                onTap: (() -> Void)? = nil) {
        self.text = text
        self.systemImage = systemImage
        self.style = semantic.style(for: Appearance())
        self.size = size
        self.customHorizontal = nil
        self.customVertical = nil
        self.customFont = nil
        self.onTap = onTap
    }

    // MARK: - Body

    // Core label stack used by the pill visuals
    @ViewBuilder
    private var labelContent: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .imageScale(.medium)
                    .accessibilityHidden(true)
            }
            Text(text)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }

    // Visual capsule rendering without interaction wrapping
    @ViewBuilder
    private var visual: some View {
        let (bg, stroke, fg) = colors(for: style)
        let paddings = (customHorizontal ?? size.paddings.horizontal, customVertical ?? size.paddings.vertical)
        let font = customFont ?? size.font

        labelContent
            .font(font)
            .foregroundStyle(fg)
            .padding(.horizontal, paddings.0)
            .padding(.vertical, paddings.1)
            .background(bg, in: Capsule())
            .overlay(
                Capsule().strokeBorder(strokeColor(base: stroke), lineWidth: stroke == .clear ? 0 : 1)
            )
            .contentShape(Capsule())
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(text))
    }

    public var body: some View {
        Group {
            if let onTap {
                Button(action: onTap) { visual }
                    .buttonStyle(PlainScaleButtonStyle())
                    .accessibilityAddTraits(.isButton)
            } else {
                visual
            }
        }
    }

    // MARK: - Color helpers
    private func colors(for style: Style) -> (bg: Color, stroke: Color, fg: Color) {
        switch style {
        case let .filled(tint, text):
            return (tint, .clear, text)
        case let .outline(tint, text):
            return (.clear, tint, text)
        case let .prominent(tint, text):
            return (tint, .clear, text)
        }
    }

    private func strokeColor(base: Color) -> Color {
        guard base != .clear else { return .clear }
        if colorScheme == .dark { return Appearance().outlineStrokeDark }
        return base.opacity(0.9)
    }
}

// MARK: - Convenience presets
public extension Pill {
    static func service(_ name: String, size: Size = .sm) -> Pill {
        Pill(name, semantic: .neutral, size: size)
    }

    static func metric(_ text: String, color: Color, size: Size = .sm) -> Pill {
        Pill(text: text, style: .filled(tint: color.opacity(0.12), text: color), size: size)
    }

    static func genderMale(_ text: String = "Male", size: Size = .sm) -> Pill {
        Pill(text, semantic: .genderMale, size: size)
    }

    static func genderFemale(_ text: String = "Female", size: Size = .sm) -> Pill {
        Pill(text, semantic: .genderFemale, size: size)
    }

    static func success(_ text: String, systemImage: String? = "checkmark.circle.fill", size: Size = .sm) -> Pill {
        Pill(text, systemImage: systemImage, semantic: .success, size: size)
    }

    static func warning(_ text: String, systemImage: String? = "exclamationmark.triangle.fill", size: Size = .sm) -> Pill {
        Pill(text, systemImage: systemImage, semantic: .warning, size: size)
    }

    static func danger(_ text: String, systemImage: String? = "xmark.octagon.fill", size: Size = .sm) -> Pill {
        Pill(text, systemImage: systemImage, semantic: .danger, size: size)
    }
    
    static func selectable(_ text: String,
                           systemImage: String? = nil,
                           isSelected: Binding<Bool>,
                           tint: Color,
                           size: Size = .sm,
                           onToggle: ((Bool) -> Void)? = nil) -> SelectablePill {
        SelectablePill(text, systemImage: systemImage, isSelected: isSelected, tint: tint, size: size, onToggle: onToggle)
    }
}

// MARK: - Small utility
private extension Color {
    func darkerIfNeeded() -> Color { self.opacity(0.9) }
}

// Subtle pressed feedback for tappable pills
private struct PlainScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Selectable wrapper
public struct SelectablePill: View {
    @Binding private var isSelected: Bool
    private let text: String
    private let systemImage: String?
    private let size: Pill.Size
    private let tint: Color
    private let onToggle: ((Bool) -> Void)?

    public init(_ text: String,
                systemImage: String? = nil,
                isSelected: Binding<Bool>,
                tint: Color,
                size: Pill.Size = .sm,
                onToggle: ((Bool) -> Void)? = nil) {
        self.text = text
        self.systemImage = systemImage
        self._isSelected = isSelected
        self.tint = tint
        self.size = size
        self.onToggle = onToggle
    }

    public var body: some View {
        let selectedStyle: Pill.Style = .prominent(tint: tint, text: .white)
        let unselectedStyle: Pill.Style = .outline(tint: tint.opacity(0.35), text: tint)

        Pill(text: text,
             systemImage: systemImage,
             style: isSelected ? selectedStyle : unselectedStyle,
             size: size,
             onTap: {
                 withAnimation(.easeInOut(duration: 0.15)) { isSelected.toggle() }
                 onToggle?(isSelected)
             })
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Preview
struct Pill_Previews: PreviewProvider {
    static var previews: some View {
        VStack(alignment: .leading, spacing: 12) {
            Group { // sizes
                HStack { Pill("XS", semantic: .info, size: .xs); Pill("SM", semantic: .success, size: .sm); Pill("MD", semantic: .warning, size: .md); Pill("LG", semantic: .danger, size: .lg) }
            }

            Pill(text: "Bath")
            Pill(text: "Haircut", systemImage: "scissors")
            Pill(text: "$65", style: .prominent(tint: .green))
            Pill(text: "Debit", systemImage: "creditcard", style: .outline(tint: .gray.opacity(0.3)))
            HStack {
                Pill.metric("3 visits", color: .blue)
                Pill.metric("$175", color: .green)
            }
            HStack {
                Pill.genderMale()
                Pill.genderFemale()
                Pill.success("Paid")
                Pill.warning("Overdue")
                Pill.danger("Declined")
            }
            Group { // selectable demo
                HStack {
                    Pill.selectable("Bath", systemImage: "shower.fill", isSelected: .constant(true), tint: .blue)
                    Pill.selectable("Trim", systemImage: "scissors", isSelected: .constant(false), tint: .purple)
                    Pill.selectable("Nails", systemImage: "hand.raised.fill", isSelected: .constant(false), tint: .orange)
                }
            }
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
