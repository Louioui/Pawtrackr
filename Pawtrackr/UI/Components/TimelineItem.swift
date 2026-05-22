//
//  TimelineItem.swift
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

fileprivate extension Color {
    static var pawSecondaryBackground: Color {
    #if os(iOS)
        Color(UIColor.secondarySystemBackground)
    #elseif os(macOS)
        Color(nsColor: .windowBackgroundColor)
    #else
        Color.secondary.opacity(0.12)
    #endif
    }
}

/// A lightweight, design‑system–friendly timeline row: dot + optional vertical rails + your content.
/// - Safe to keep `public` (no app model types exposed).
/// - Works in `VStack`/`List`; use `showTopLine/showBottomLine` to connect rows.
/// - A11y: the rail is hidden from VoiceOver; your `content` provides semantics.
public struct TimelineItem<Content: View>: View {
    // MARK: Appearance
    public var dotSize: CGFloat
    public var railWidth: CGFloat
    public var dotColor: Color
    public var railColor: Color
    public var showTopLine: Bool
    public var showBottomLine: Bool

    // MARK: Content
    @ViewBuilder public var content: () -> Content

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var hSizeClass
    #endif

    private func scaled(_ base: CGFloat) -> CGFloat {
        switch dynamicTypeSize {
        case .accessibility3, .accessibility4, .accessibility5:
            return base * 1.45
        case .accessibility1, .accessibility2:
            return base * 1.25
        case .xxxLarge:
            return base * 1.15
        case .xxLarge:
            return base * 1.10
        case .xLarge:
            return base * 1.05
        default:
            return base
        }
    }

    // MARK: Body
    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Left rail + dot (scaled for Dynamic Type)
            let sDot = scaled(dotSize)
            let sRail = max(1, scaled(railWidth))
            #if os(iOS)
            let baseCol: CGFloat = (hSizeClass == .regular) ? 26 : 22
            #else
            let baseCol: CGFloat = 22
            #endif
            let columnWidth = max(sDot, baseCol)
            RailColumn(
                dotSize: sDot,
                railWidth: sRail,
                dotColor: dotColor,
                railColor: railColor,
                showTop: showTopLine,
                showBottom: showBottomLine,
                columnWidth: columnWidth
            )
            .accessibilityHidden(true)

            // Right user content
            content()
                .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - RailColumn
private struct RailColumn: View {
    var dotSize: CGFloat
    var railWidth: CGFloat
    var dotColor: Color
    var railColor: Color
    var showTop: Bool
    var showBottom: Bool
    var columnWidth: CGFloat

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                if showTop {
                    Rectangle()
                        .fill(railColor)
                        .frame(width: railWidth,
                               height: max(0, (geo.size.height - dotSize) / 2))
                } else {
                    Spacer(minLength: 0)
                        .frame(height: max(0, (geo.size.height - dotSize) / 2))
                }

                Circle()
                    .fill(dotColor)
                    .frame(width: dotSize, height: dotSize)
                    .overlay(
                        Circle()
                            .stroke(railColor.opacity(0.25), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.08), radius: 1, x: 0, y: 1)

                if showBottom {
                    Rectangle()
                        .fill(railColor)
                        .frame(width: railWidth,
                               height: max(0, (geo.size.height - dotSize) / 2))
                } else {
                    Spacer(minLength: 0)
                        .frame(height: max(0, (geo.size.height - dotSize) / 2))
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(width: columnWidth, alignment: .topLeading)
        .fixedSize(horizontal: true, vertical: false)
    }
}

// MARK: - Convenience builder for common text rows
public struct TimelineTextRow: View {
    public var title: String
    public var subtitle: String?
    public var amount: String?
    public var time: String?
    public var dotColor: Color
    public var railColor: Color
    public var showTopLine: Bool
    public var showBottomLine: Bool
    public var amountTint: Color

    public init(
        title: String,
        subtitle: String? = nil,
        amount: String? = nil,
        time: String? = nil,
        dotColor: Color = .accentColor,
        railColor: Color = .secondary.opacity(0.35),
        showTopLine: Bool = true,
        showBottomLine: Bool = true,
        amountTint: Color = .green
    ) {
        self.title = title
        self.subtitle = subtitle
        self.amount = amount
        self.time = time
        self.dotColor = dotColor
        self.railColor = railColor
        self.showTopLine = showTopLine
        self.showBottomLine = showBottomLine
        self.amountTint = amountTint
    }

    public var body: some View {
        TimelineItem(
            dotSize: 12,
            railWidth: 2,
            dotColor: dotColor,
            railColor: railColor,
            showTopLine: showTopLine,
            showBottomLine: showBottomLine
        ) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Spacer(minLength: 8)

                    if let amount {
                        Text(amount)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(amountTint)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(amountTint.opacity(0.12))
                            )
                            .accessibilityLabel(Text("Amount"))
                            .accessibilityValue(Text(amount))
                    }
                }

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                if let time, !time.isEmpty {
                    Text(time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.pawSecondaryBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.06))
            )
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Previews
#Preview("TimelineItem – basic") {
    VStack(spacing: 20) {
        TimelineItem(
            dotSize: 12,
            railWidth: 2,
            dotColor: .blue,
            railColor: .secondary.opacity(0.35),
            showTopLine: false,
            showBottomLine: true
        ) {
            HStack {
                Text("Checked in – Bath & Nails")
                    .font(.headline)
                Spacer()
                Text("$65.00")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12).fill(Color.pawSecondaryBackground)
            )
        }

        TimelineTextRow(
            title: "Checkout complete",
            subtitle: "Duration: 1h 12m · Cash",
            amount: "$65.00",
            time: "Aug 19, 12:41 PM",
            dotColor: .green,
            railColor: .secondary.opacity(0.35),
            showTopLine: true,
            showBottomLine: true
        )

        TimelineItem(
            dotSize: 12,
            railWidth: 2,
            dotColor: .gray,
            railColor: .secondary.opacity(0.35),
            showTopLine: true,
            showBottomLine: false
        ) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Visit note")
                    .font(.headline)
                Text("Owner requested hypoallergenic shampoo.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12).fill(Color.pawSecondaryBackground)
            )
        }
    }
    .padding()
    #if os(macOS)
    .frame(width: 560)
    #endif
}
