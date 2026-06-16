//
//  WalkthroughOverlay.swift
//  Pawtrackr
//
//  The visual layer of the guided tour: dims the whole window, cuts a glowing
//  hole around the current step's control, points an arrow at it, and floats a
//  bubble explaining what it is and why it helps. Hosted at the navigation root
//  so it spotlights the sidebar (Mac/iPad) and the tab bar (iPhone) alike.
//
//  Bubble placement adapts to where the target lives: a sidebar row on the left
//  gets a bubble to its trailing side (arrow pointing left); a bottom tab-bar
//  slot gets a bubble above it (arrow pointing down).
//

import SwiftUI

extension View {
    /// Hosts the guided-tour overlay above this view's content. Anchors registered
    /// with `.walkthroughAnchor(_:)` anywhere in the subtree are resolved here, so
    /// attach this at the navigation root that contains the sidebar / tab bar.
    func walkthroughOverlay(_ controller: WalkthroughController) -> some View {
        overlayPreferenceValue(WalkthroughAnchorPreferenceKey.self) { anchors in
            GeometryReader { proxy in
                if controller.isActive, let step = controller.currentStep {
                    // Prefer the live anchor; fall back to a computed rect for
                    // targets SwiftUI won't anchor (iPhone tab-bar items).
                    let target = anchors[step.anchor].map { proxy[$0] }
                        ?? walkthroughFallbackRect(step.fallback, in: proxy)
                    WalkthroughOverlayView(
                        step: step,
                        targetRect: target,
                        containerSize: proxy.size,
                        controller: controller
                    )
                }
            }
            .ignoresSafeArea()
        }
    }
}

/// Computes a spotlight rect for targets that can't be anchored. Currently only
/// the iPhone bottom tab bar, whose `.tabItem` frames SwiftUI does not expose.
private func walkthroughFallbackRect(_ fallback: SpotlightFallback, in proxy: GeometryProxy) -> CGRect? {
    switch fallback {
    case .none:
        return nil
    case .tabBarItem(let index, let count):
        guard count > 0, index >= 0, index < count else { return nil }
        let tabBarHeight: CGFloat = 49
        let bottomInset = proxy.safeAreaInsets.bottom
        let slot = proxy.size.width / CGFloat(count)
        let centerX = slot * (CGFloat(index) + 0.5)
        let centerY = proxy.size.height - bottomInset - tabBarHeight / 2
        let w = min(slot - 16, 60)
        let h: CGFloat = 44
        return CGRect(x: centerX - w / 2, y: centerY - h / 2, width: w, height: h)
    }
}

private enum ArrowDirection { case up, down, left, right }

/// An isosceles triangle pointing in one of four directions — the bubble's
/// pointer into the spotlight.
private struct ArrowTriangle: Shape {
    var direction: ArrowDirection
    func path(in rect: CGRect) -> Path {
        var p = Path()
        switch direction {
        case .up:
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        case .down:
            p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        case .left:
            p.move(to: CGPoint(x: rect.minX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        case .right:
            p.move(to: CGPoint(x: rect.maxX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
        p.closeSubpath()
        return p
    }
}

private enum BubblePlacement { case below, above, trailing }

private struct WalkthroughOverlayView: View {
    let step: WalkthroughStep
    let targetRect: CGRect?
    let containerSize: CGSize
    let controller: WalkthroughController

    private let dimOpacity = 0.74
    private let spotlightPadding: CGFloat = 10
    private let bubbleMaxWidth: CGFloat = 440

    /// Inflated rect we actually cut/ring around the target.
    private var spotlight: CGRect? {
        guard let r = targetRect, r.width > 0, r.height > 0 else { return nil }
        return r.insetBy(dx: -spotlightPadding, dy: -spotlightPadding)
    }

    /// Where the bubble goes relative to the spotlight, chosen from the target's
    /// position: bottom tab bar → above; left-column sidebar row → trailing;
    /// otherwise the opposite vertical half.
    private var placement: BubblePlacement {
        guard let s = spotlight else { return .below }
        if s.midY > containerSize.height * 0.72 { return .above }          // tab bar
        if s.maxX < containerSize.width * 0.45 { return .trailing }        // sidebar
        return s.midY < containerSize.height * 0.5 ? .below : .above
    }

    var body: some View {
        ZStack {
            dimLayer
            spotlightRing
            spotlightTapTarget
            bubble
        }
        // Interpolate the spotlight + bubble both when the step changes and when
        // the target frame moves (e.g. a macOS window resize mid-tour).
        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: step.id)
        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: targetRect)
    }

    // MARK: Dim + cutout

    private var dimLayer: some View {
        Canvas { ctx, size in
            var region = Path(CGRect(origin: .zero, size: size))
            if let s = spotlight {
                switch step.shape {
                case .circle:
                    let d = max(s.width, s.height)
                    region.addEllipse(in: CGRect(x: s.midX - d / 2, y: s.midY - d / 2, width: d, height: d))
                case .roundedRect(let cr):
                    region.addRoundedRect(in: s, cornerSize: CGSize(width: cr, height: cr), style: .continuous)
                }
            }
            // Even-odd fill leaves the cutout transparent — robust, no blend modes.
            ctx.fill(region, with: .color(.black.opacity(dimOpacity)), style: FillStyle(eoFill: true))
        }
        .contentShape(Rectangle())
        .onTapGesture { /* swallow taps/clicks on the dimmed area */ }
    }

    // MARK: Glowing ring

    @ViewBuilder
    private var spotlightRing: some View {
        if let s = spotlight {
            Group {
                switch step.shape {
                case .circle:
                    let d = max(s.width, s.height)
                    Circle()
                        .stroke(Color.white.opacity(0.95), lineWidth: 2.5)
                        .frame(width: d, height: d)
                        .position(x: s.midX, y: s.midY)
                case .roundedRect(let cr):
                    RoundedRectangle(cornerRadius: cr, style: .continuous)
                        .stroke(Color.white.opacity(0.95), lineWidth: 2.5)
                        .frame(width: s.width, height: s.height)
                        .position(x: s.midX, y: s.midY)
                }
            }
            .shadow(color: DS.ColorToken.primary.opacity(0.8), radius: 10)
            .allowsHitTesting(false)
        }
    }

    /// Invisible tap target over the highlighted control: tapping it advances, so
    /// the tour feels like "tap the thing" without risking real navigation.
    @ViewBuilder
    private var spotlightTapTarget: some View {
        if let s = spotlight {
            Color.white.opacity(0.001)
                .frame(width: s.width, height: s.height)
                .contentShape(Rectangle())
                .position(x: s.midX, y: s.midY)
                .onTapGesture { controller.advance() }
        }
    }

    // MARK: Bubble + arrow

    @ViewBuilder
    private var bubble: some View {
        switch placement {
        case .below: verticalBubble(below: true)
        case .above: verticalBubble(below: false)
        case .trailing: trailingBubble
        }
    }

    /// Bubble above or below the spotlight (tab bar / general case).
    private func verticalBubble(below: Bool) -> some View {
        let gap: CGFloat = 16
        let topInset = below ? min((spotlight?.maxY ?? 0) + gap, containerSize.height * 0.62) : 0
        let bottomInset = below ? 0 : min(containerSize.height - (spotlight?.minY ?? containerSize.height) + gap, containerSize.height * 0.62)

        return VStack(spacing: 0) {
            if below { verticalArrow(.up) }
            bubbleCard
            if !below { verticalArrow(.down) }
        }
        .frame(maxWidth: bubbleMaxWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: below ? .top : .bottom)
        .padding(.horizontal, 20)
        .padding(.top, topInset)
        .padding(.bottom, bottomInset)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    /// Bubble to the trailing side of the spotlight (sidebar row on Mac/iPad).
    private var trailingBubble: some View {
        let gap: CGFloat = 12
        let leadingInset = min((spotlight?.maxX ?? 0) + gap, containerSize.width * 0.55)
        let topInset = max(12, min((spotlight?.minY ?? 0) - 8, containerSize.height - 260))

        return HStack(alignment: .top, spacing: 0) {
            ArrowTriangle(direction: .left)
                .fill(DS.ColorToken.surface)
                .frame(width: 11, height: 22)
                .padding(.top, 16)
            bubbleCard
        }
        .frame(maxWidth: bubbleMaxWidth, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.leading, leadingInset)
        .padding(.top, topInset)
        .padding(.trailing, 16)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    /// Up/down pointer, nudged horizontally toward the target's center.
    private func verticalArrow(_ dir: ArrowDirection) -> some View {
        let targetX = spotlight?.midX ?? containerSize.width / 2
        let rawOffset = targetX - containerSize.width / 2
        let limit = (min(bubbleMaxWidth, containerSize.width - 40) / 2) - 24
        let offset = max(-limit, min(limit, rawOffset))
        return ArrowTriangle(direction: dir)
            .fill(DS.ColorToken.surface)
            .frame(width: 22, height: 11)
            .offset(x: offset)
    }

    private var bubbleCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: step.icon)
                    .font(.headline)
                    .foregroundStyle(DS.ColorToken.primary)
                Text(step.title)
                    .font(.headline)
                Spacer(minLength: 8)
                Text("\(controller.stepNumber) / \(controller.stepCount)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Text(step.directive)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DS.ColorToken.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(step.purpose)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button(AppLocalization.localized("tour.skip", value: "Skip tour")) {
                    controller.skip()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)

                Spacer()

                Button {
                    controller.advance()
                } label: {
                    HStack(spacing: 6) {
                        Text(controller.isLastStep
                             ? AppLocalization.localized("tour.done", value: "Done")
                             : AppLocalization.localized("tour.next", value: "Next"))
                            .fontWeight(.semibold)
                        Image(systemName: controller.isLastStep ? "checkmark" : "arrow.right")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(DS.ColorToken.primary)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 2)
        }
        .padding(16)
        .background(DS.ColorToken.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.28), radius: 18, x: 0, y: 8)
    }
}
