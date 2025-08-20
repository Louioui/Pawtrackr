//
//  FlowLayout.swift
//  Pawtrackr
//
//  A lightweight wrapping layout for chips/pills/tags using SwiftUI's `Layout` protocol (iOS 16+).
//  Usage:
//    FlowLayout(spacing: 8) {
//        ForEach(items) { item in Pill(text: item.name) }
//    }
//
//  Created by mac on 8/14/25.
//  Updated by mac on 8/16/25.
//

import SwiftUI

public struct FlowLayout<Content: View>: View {
    private let spacing: CGFloat
    private let rowSpacing: CGFloat
    @ViewBuilder private var content: () -> Content

    public init(spacing: CGFloat = 8, rowSpacing: CGFloat? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.rowSpacing = rowSpacing ?? spacing
        self.content = content
    }

    public var body: some View {
        _FlowLayout(spacing: spacing, rowSpacing: rowSpacing) {
            content()
        }
    }
}

// MARK: - Layout engine

fileprivate struct _FlowLayout: Layout {
    let spacing: CGFloat
    let rowSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }

        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentRowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let subviewSize = subview.sizeThatFits(.unspecified)
            if currentX > 0 && currentX + subviewSize.width > maxWidth { // Wrap to next row
                totalHeight += currentRowHeight + rowSpacing
                totalWidth = max(totalWidth, currentX - spacing)
                currentX = 0
                currentRowHeight = 0
            }
            currentX += subviewSize.width + spacing
            currentRowHeight = max(currentRowHeight, subviewSize.height)
        }

        totalHeight += currentRowHeight
        totalWidth = max(totalWidth, currentX - spacing)

        let width = proposal.width ?? totalWidth
        return CGSize(width: width, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }

        let maxWidth = bounds.width
        var x: CGFloat = 0
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let subviewSize = subview.sizeThatFits(.unspecified)
            if x > 0 && x + subviewSize.width > maxWidth { // Wrap to next row
                y += rowHeight + rowSpacing
                x = 0
                rowHeight = 0
            }

            subview.place(at: CGPoint(x: bounds.minX + x, y: y), anchor: .topLeading, proposal: .unspecified)
            x += subviewSize.width + spacing
            rowHeight = max(rowHeight, subviewSize.height)
        }
    }
}


// MARK: - Preview

struct FlowLayout_Previews: PreviewProvider {
    static let sample = ["Bath","Haircut","Nails","Ears","Teeth","De-shed","Special Shampoo","De-mat"]
    static var previews: some View {
        ScrollView {
            FlowLayout(spacing: 8) {
                ForEach(sample, id: \.self) { s in
                    Text(s)
                        .font(.caption)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.gray.opacity(0.12), in: Capsule())
                }
            }
            .padding()
        }
    }
}
