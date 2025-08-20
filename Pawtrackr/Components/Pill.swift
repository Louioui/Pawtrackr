//
//  Pill.swift
//  Pawtrackr
//
//  Lightweight chip/pill used for services, tags, and summary counts.
//
//  Created by mac on 8/14/25.
//  Updated by mac on 8/16/25.
//

import SwiftUI

public struct Pill: View {
    public enum Style {
        case filled(tint: Color = Color(.secondarySystemFill), text: Color = .primary)
        case outline(tint: Color = Color.gray.opacity(0.25), text: Color = .primary)
        case prominent(tint: Color, text: Color = .white)
    }

    private let text: String
    private let systemImage: String?
    private let style: Style
    private let horizontal: CGFloat
    private let vertical: CGFloat
    private let font: Font

    public init(text: String,
                systemImage: String? = nil,
                style: Style = .filled(),
                horizontal: CGFloat = 10,
                vertical: CGFloat = 6,
                font: Font = .caption) {
        self.text = text
        self.systemImage = systemImage
        self.style = style
        self.horizontal = horizontal
        self.vertical = vertical
        self.font = font
    }

    @ViewBuilder
    private var labelContent: some View {
        if let sys = systemImage {
            Label {
                Text(text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            } icon: {
                Image(systemName: sys)
                    .imageScale(.small)
            }
        } else {
            Text(text)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }

    public var body: some View {
        let (bg, stroke, fg) = colors(for: style)
        labelContent
            .font(font)
            .foregroundStyle(fg)
            .padding(.horizontal, horizontal)
            .padding(.vertical, vertical)
            .background(bg, in: Capsule())
            .overlay(
                Capsule().strokeBorder(stroke, lineWidth: stroke == .clear ? 0 : 1)
            )
            .contentShape(Capsule())
            .accessibilityLabel(Text(text))
    }

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
}

// MARK: - Convenience presets

public extension Pill {
    static func service(_ name: String) -> Pill {
        Pill(text: name, style: .filled(tint: .gray.opacity(0.12), text: .primary))
    }

    static func metric(_ text: String, color: Color) -> Pill {
        Pill(text: text, style: .filled(tint: color.opacity(0.12), text: color))
    }
}

// MARK: - Preview

struct Pill_Previews: PreviewProvider {
    static var previews: some View {
        VStack(alignment: .leading, spacing: 12) {
            Pill(text: "Bath")
            Pill(text: "Haircut", systemImage: "scissors")
            Pill(text: "$65", style: .prominent(tint: .green))
            Pill(text: "Debit", systemImage: "creditcard", style: .outline(tint: .gray.opacity(0.3)))
            HStack {
                Pill.metric("3 visits", color: .blue)
                Pill.metric("$175", color: .green)
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
