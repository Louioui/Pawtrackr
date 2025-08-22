//
//  Chip.swift
//  Pawtrackr
//
//  Created by mac on 8/20/25.
//

import SwiftUI

#if os(iOS) || os(tvOS) || os(visionOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

private var _deviceScale: CGFloat {
#if os(iOS) || os(tvOS) || os(visionOS)
    return UIScreen.main.scale
#elseif os(macOS)
    return NSScreen.main?.backingScaleFactor ?? 2.0
#else
    return 2.0
#endif
}

public struct Chip: View {
    public enum Style { case filled, outline, tinted }
    public enum Size { case s, m, l }

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var scheme

    private let title: String
    private let systemImage: String?
    @Binding private var isSelected: Bool
    private let style: Style
    private let size: Size
    private let cornerRadius: CGFloat
    private let onTap: (() -> Void)?

    public init(
        _ title: String,
        systemImage: String? = nil,
        isSelected: Binding<Bool> = .constant(false),
        style: Style = .filled,
        size: Size = .m,
        cornerRadius: CGFloat = 999,
        onTap: (() -> Void)? = nil
    ) {
        self.title = title
        self.systemImage = systemImage
        self._isSelected = isSelected
        self.style = style
        self.size = size
        self.cornerRadius = cornerRadius
        self.onTap = onTap
    }

    public var body: some View {
        let config = metrics(for: size)
        let colors = palette(style: style, selected: isSelected, scheme: scheme)

        Button {
            if let onTap { onTap() } else { isSelected.toggle() }
        } label: {
            label(config: config, colors: colors)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(.isButton)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(colors.bg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(colors.stroke, lineWidth: colors.stroke == .clear ? 0 : 1 / _deviceScale)
        )
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .opacity(isEnabled ? 1 : 0.55)
    }

    @ViewBuilder
    private func label(config: (padV: CGFloat, padH: CGFloat, font: Font, iconSize: CGFloat),
                       colors: (bg: Color, fg: Color, stroke: Color)) -> some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: IconSizeToken.sm.symbolPointSize, weight: .semibold, design: .default))
            }
            Text(title)
                .font(config.font)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(colors.fg)
        .padding(.vertical, config.padV)
        .padding(.horizontal, config.padH)
    }

    private func metrics(for size: Size) -> (padV: CGFloat, padH: CGFloat, font: Font, iconSize: CGFloat) {
        switch size {
        case .s: return (6, 10, .system(.footnote, design: .rounded), IconSizeToken.sm.diameter)
        case .m: return (8, 12, .system(.callout,  design: .rounded), IconSizeToken.sm.diameter)
        case .l: return (10, 14, .system(.body,     design: .rounded), IconSizeToken.sm.diameter)
        }
    }

    private func palette(style: Style, selected: Bool, scheme: ColorScheme)
        -> (bg: Color, fg: Color, stroke: Color)
    {
        // Tokens
        let tint = Color("AccentColor", bundle: .main)
        #if os(iOS) || os(tvOS) || os(visionOS)
        let sysSecondaryBG = Color(.secondarySystemBackground)
        let sysBG = Color(.systemBackground)
        let sysGroupedBG = Color(.systemGroupedBackground)
        #elseif os(macOS)
        let sysSecondaryBG = Color(nsColor: .textBackgroundColor)
        let sysBG = Color(nsColor: .windowBackgroundColor)
        let sysGroupedBG = Color(nsColor: .underPageBackgroundColor)
        #else
        let sysSecondaryBG = Color.gray.opacity(0.12)
        let sysBG = Color.white
        let sysGroupedBG = Color.gray.opacity(0.08)
        #endif
        let baseBG = scheme == .dark ? sysSecondaryBG : sysBG
        let text = scheme == .dark ? Color.white.opacity(0.9) : Color.black.opacity(0.85)
        let stroke = Color.primary.opacity(scheme == .dark ? 0.15 : 0.12)

        switch style {
        case .filled:
            if selected {
                return (tint, .white, .clear)
            } else {
                return (baseBG, text, stroke)
            }
        case .outline:
            if selected {
                return (tint.opacity(scheme == .dark ? 0.25 : 0.12), tint, tint)
            } else {
                return (.clear, text, stroke)
            }
        case .tinted:
            let bg = tint.opacity(selected ? (scheme == .dark ? 0.28 : 0.18) : (scheme == .dark ? 0.18 : 0.12))
            let fg = selected ? tint : text
            return (bg, fg, .clear)
        }
    }
}

// MARK: - Convenience builders

public extension Chip {
    static func selectable(_ title: String,
                           systemImage: String? = nil,
                           isSelected: Binding<Bool>,
                           size: Size = .m,
                           style: Style = .filled) -> Chip {
        Chip(title, systemImage: systemImage, isSelected: isSelected, style: style, size: size)
    }

    static func action(_ title: String,
                       systemImage: String? = nil,
                       size: Size = .m,
                       style: Style = .filled,
                       onTap: @escaping () -> Void) -> Chip {
        Chip(title, systemImage: systemImage, style: style, size: size, onTap: onTap)
    }
}

// MARK: - Preview

struct Chip_Previews: PreviewProvider {
    struct Demo: View {
        @State var bath = true
        @State var trim = true
        @State var nails = false

        var body: some View {
            VStack(spacing: 12) {
                HStack {
                    Chip.selectable("Bath", systemImage: "shower", isSelected: $bath)
                    Chip.selectable("Trim", systemImage: "scissors", isSelected: $trim, style: .tinted)
                    Chip.selectable("Nail Clip", systemImage: "pawprint", isSelected: $nails, style: .outline)
                }
                HStack {
                    Chip.action("Cash", systemImage: "banknote") {}
                    Chip.action("Debit", systemImage: "creditcard") {}
                    Chip.action("Zelle", systemImage: "rectangle.portrait.and.arrow.forward") {}
                }
            }
            #if os(iOS) || os(tvOS) || os(visionOS)
            .background(Color(.systemGroupedBackground))
            #elseif os(macOS)
            .background(Color(nsColor: .underPageBackgroundColor))
            #else
            .background(Color.gray.opacity(0.06))
            #endif
        }
    }
    static var previews: some View { Demo() }
}
