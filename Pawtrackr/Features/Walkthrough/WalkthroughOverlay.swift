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

/// Which slice of the tour an overlay is responsible for. On iPhone (and iPad
/// split-screen compact) one overlay owns everything. On a `NavigationSplitView`
/// (iPad regular / Mac) the sidebar and detail are separate hosting contexts, and
/// a single root overlay resolves DETAIL-column anchors without the sidebar's
/// horizontal offset — so the spotlight spans the whole window instead of framing
/// the element. Splitting the work fixes that: the root overlay handles the
/// sidebar nav rows (which it CAN resolve), and an overlay hosted inside the
/// detail column handles content steps (whose anchors resolve tightly there).
enum WalkthroughOverlayScope {
    case all          // single overlay owns every step (iPhone / compact)
    case navigation   // only the primary sidebar nav-row steps
    case content      // everything except the primary nav rows

    private static let navigationAnchors: Set<WalkthroughAnchorID> = [
        .dashboard, .clients, .insights, .settings
    ]

    func handles(_ step: WalkthroughStep) -> Bool {
        switch self {
        case .all: return true
        case .navigation: return Self.navigationAnchors.contains(step.anchor)
        case .content: return !Self.navigationAnchors.contains(step.anchor)
        }
    }
}

extension View {
    /// Hosts the guided-tour overlay above this view's content. Anchors registered
    /// with `.walkthroughAnchor(_:)` anywhere in the subtree are resolved here, so
    /// attach this at the navigation root that contains the sidebar / tab bar.
    /// - Parameter presenting: which modal this overlay belongs to. The root
    ///   overlay passes `nil` and renders only main-UI steps; a sheet passes its
    ///   own presentation and renders only that sheet's steps. Without this, the
    ///   root overlay also rendered sheet steps and pointed its `.topTrailingAction`
    ///   fallback at nothing on the main window.
    /// - Parameter scope: which steps this overlay should draw. See
    ///   `WalkthroughOverlayScope`. Defaults to `.all` (iPhone single overlay).
    func walkthroughOverlay(
        _ controller: WalkthroughController,
        presenting: WalkthroughPresentation? = nil,
        scope: WalkthroughOverlayScope = .all
    ) -> some View {
        overlayPreferenceValue(WalkthroughAnchorPreferenceKey.self) { anchors in
            GeometryReader { proxy in
                if controller.isActive, let step = controller.currentStep,
                   step.presents == presenting, scope.handles(step) {
                    // Prefer the live anchor; fall back to a computed rect for
                    // targets SwiftUI won't anchor (iPhone tab-bar items).
                    let target = anchors[step.anchor].map { proxy[$0] }
                        ?? walkthroughFallbackRect(step.fallback, in: proxy)
                    WalkthroughOverlayView(
                        step: step,
                        targetRect: target,
                        containerSize: proxy.size,
                        containerInsets: proxy.safeAreaInsets,
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
    case .topTrailingAction:
        let isCompactPhone = proxy.size.width < 430
        let width: CGFloat = isCompactPhone ? 64 : 118
        let height: CGFloat = isCompactPhone ? 48 : 44
        let margin: CGFloat = isCompactPhone ? 10 : 16
        let x = proxy.size.width - proxy.safeAreaInsets.trailing - margin - width
        // The overlay ignores safe areas, so `safeAreaInsets.top` can be zero on
        // iPhone. Keep compact highlights down in the navigation bar where the
        // blue Create check lives, instead of circling the status icons.
        let minimumTop: CGFloat = isCompactPhone ? 66 : 44
        let y = max(proxy.safeAreaInsets.top + margin, minimumTop)
        return CGRect(x: max(margin, x), y: y, width: width, height: height)
    case .bottomTrailingAction:
        let width: CGFloat = 118
        let height: CGFloat = 44
        let margin: CGFloat = 16
        let x = proxy.size.width - proxy.safeAreaInsets.trailing - margin - width
        let y = proxy.size.height - proxy.safeAreaInsets.bottom - margin - height
        return CGRect(x: max(margin, x), y: max(margin, y), width: width, height: height)
    case .topTrailingIcon:
        // A single compact toolbar icon (macOS "+"). Keep it narrow so the
        // spotlight lands on just that button, not the neighboring delete action.
        let size: CGFloat = 48
        let margin: CGFloat = 14
        let x = proxy.size.width - proxy.safeAreaInsets.trailing - margin - size
        let y = proxy.safeAreaInsets.top + margin
        return CGRect(x: max(margin, x), y: y, width: size, height: size)
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

private enum BubblePlacement { case below, above, trailing, center }

private struct WalkthroughOverlayView: View {
    let step: WalkthroughStep
    let targetRect: CGRect?
    let containerSize: CGSize
    let containerInsets: EdgeInsets
    let controller: WalkthroughController

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Gentle, continuous "breathing" of the spotlight ring to draw the eye to
    /// the highlighted control. Disabled under Reduce Motion.
    @State private var ringPulse = false

    private let spotlightPadding: CGFloat = 10
    private let arrowExtent: CGFloat = 11

    private var dimOpacity: Double {
        #if os(macOS)
        return 0.58
        #else
        return isCompactViewport ? 0.62 : 0.54
        #endif
    }

    private var bubbleMaxWidth: CGFloat {
        if containerSize.width >= 900 { return 500 }
        if containerSize.width >= 620 { return 460 }
        return 370
    }

    private var bubbleMinHeight: CGFloat {
        isCompactViewport ? 150 : 164
    }

    private var isCompactViewport: Bool {
        containerSize.width < 430 || containerSize.height < 760
    }

    private var bubbleHorizontalPadding: CGFloat {
        isCompactViewport ? 16 : 20
    }

    private var bubbleWidth: CGFloat {
        min(bubbleMaxWidth, max(260, containerSize.width - bubbleHorizontalPadding * 2))
    }

    private var safeTopPadding: CGFloat {
        max(containerInsets.top + 8, 16)
    }

    private var safeBottomPadding: CGFloat {
        max(containerInsets.bottom + 8, 16)
    }

    private var bubbleGap: CGFloat {
        isCompactViewport ? 10 : 16
    }

    private var readableBubbleMaxHeight: CGFloat {
        min(isCompactViewport ? 300 : 380, max(220, containerSize.height - safeTopPadding - safeBottomPadding - 20))
    }

    private var bubbleCardPadding: CGFloat {
        isCompactViewport ? 13 : 16
    }

    private var bubbleChromeHeightEstimate: CGFloat {
        isCompactViewport ? 124 : 140
    }

    private var availableAboveSpotlight: CGFloat {
        guard let s = spotlight else { return readableBubbleMaxHeight }
        return s.minY - bubbleGap - arrowExtent - safeTopPadding
    }

    private var availableBelowSpotlight: CGFloat {
        guard let s = spotlight else { return readableBubbleMaxHeight }
        return containerSize.height - s.maxY - bubbleGap - arrowExtent - safeBottomPadding
    }

    /// Inflated rect we actually cut/ring around the target.
    private var spotlight: CGRect? {
        guard let r = targetRect, r.width > 0, r.height > 0 else { return nil }
        let padded = r.insetBy(dx: -spotlightPadding, dy: -spotlightPadding)
        let bounds = CGRect(
            x: max(6, containerInsets.leading + 6),
            y: max(6, containerInsets.top + 6),
            width: max(1, containerSize.width - containerInsets.leading - containerInsets.trailing - 12),
            height: max(1, containerSize.height - containerInsets.top - containerInsets.bottom - 12)
        )
        let clamped = padded.intersection(bounds)
        return clamped.isNull || clamped.isEmpty ? padded : clamped
    }

    /// Where the bubble goes relative to the spotlight, chosen from the target's
    /// position: bottom tab bar → above; left-column sidebar row → trailing;
    /// otherwise the opposite vertical half.
    private var placement: BubblePlacement {
        guard let s = spotlight else { return .center }
        if s.midY > containerSize.height * 0.72 { return .above }          // tab bar
        if containerSize.width >= 620, s.maxX < containerSize.width * 0.45 { return .trailing } // sidebar

        let preferredMinimum = isCompactViewport ? 280.0 : 320.0
        if availableBelowSpotlight >= preferredMinimum || availableBelowSpotlight >= availableAboveSpotlight {
            return .below
        }
        return .above
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
        .allowsHitTesting(!step.allowsTargetInteraction)
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
            .shadow(color: DS.ColorToken.primary.opacity(ringPulse ? 0.95 : 0.65), radius: ringPulse ? 16 : 8)
            .scaleEffect(ringPulse ? 1.035 : 1.0)
            .allowsHitTesting(false)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    ringPulse = true
                }
            }
        }
    }

    /// Invisible tap target over the highlighted control: tapping it advances, so
    /// the tour feels like "tap the thing" without risking real navigation.
    @ViewBuilder
    private var spotlightTapTarget: some View {
        if let s = spotlight, !step.allowsTargetInteraction {
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
        case .center: centerBubble
        }
    }

    /// Bubble above or below the spotlight (tab bar / general case).
    private func verticalBubble(below: Bool) -> some View {
        let availableHeight = below ? availableBelowSpotlight : availableAboveSpotlight
        let cardMaxHeight = boundedBubbleHeight(for: availableHeight)
        let topInset = below ? min((spotlight?.maxY ?? 0) + bubbleGap, containerSize.height - safeBottomPadding - cardMaxHeight - arrowExtent) : 0
        let bottomInset = below ? 0 : min(containerSize.height - (spotlight?.minY ?? containerSize.height) + bubbleGap, containerSize.height - safeTopPadding - cardMaxHeight - arrowExtent)

        return VStack(spacing: 0) {
            if below { verticalArrow(.up) }
            bubbleCard(maxHeight: cardMaxHeight)
                .frame(maxHeight: cardMaxHeight, alignment: .top)
            if !below { verticalArrow(.down) }
        }
        .frame(maxWidth: bubbleWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: below ? .top : .bottom)
        // Slide horizontally toward the target so the arrow can reach an
        // off-center control on wide screens (iPad / Mac). No-op on iPhone,
        // where the bubble already spans the full width.
        .offset(x: verticalBubbleCenterX - containerSize.width / 2)
        .padding(.top, topInset)
        .padding(.bottom, bottomInset)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    /// Bubble to the trailing side of the spotlight (sidebar row on Mac/iPad).
    private var trailingBubble: some View {
        let gap: CGFloat = 12
        let leadingInset = min((spotlight?.maxX ?? 0) + gap, containerSize.width * 0.55)
        let cardMaxHeight = boundedBubbleHeight(for: containerSize.height - safeTopPadding - safeBottomPadding)
        let topInset = max(safeTopPadding, min((spotlight?.minY ?? 0) - 8, containerSize.height - safeBottomPadding - cardMaxHeight))

        return HStack(alignment: .top, spacing: 0) {
            ArrowTriangle(direction: .left)
                .fill(DS.ColorToken.surface)
                .frame(width: 11, height: 22)
                .padding(.top, 16)
            bubbleCard(maxHeight: cardMaxHeight)
                .frame(maxHeight: cardMaxHeight, alignment: .top)
        }
        .frame(maxWidth: bubbleWidth, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.leading, leadingInset)
        .padding(.top, topInset)
        .padding(.trailing, 16)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    /// Centered fallback when a step is informational or the target hasn't
    /// appeared yet. This keeps the tour readable instead of silently dropping
    /// the bubble.
    private var centerBubble: some View {
        bubbleCard(maxHeight: boundedBubbleHeight(for: containerSize.height - safeTopPadding - safeBottomPadding))
            .frame(maxHeight: boundedBubbleHeight(for: containerSize.height - safeTopPadding - safeBottomPadding), alignment: .center)
            .frame(maxWidth: bubbleWidth)
            .padding(.horizontal, bubbleHorizontalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    private func boundedBubbleHeight(for availableHeight: CGFloat) -> CGFloat {
        min(readableBubbleMaxHeight, max(bubbleMinHeight, availableHeight))
    }

    /// Where the vertical bubble's horizontal center sits. On iPhone the bubble
    /// spans the width, so this stays at screen center (no shift). On wide screens
    /// it slides toward the target — clamped to keep the bubble fully on screen —
    /// so the arrow can actually reach an off-center control instead of pointing
    /// at empty space.
    private var verticalBubbleCenterX: CGFloat {
        let targetX = spotlight?.midX ?? containerSize.width / 2
        let halfWidth = bubbleWidth / 2
        let minCenter = halfWidth + bubbleHorizontalPadding
        let maxCenter = containerSize.width - halfWidth - bubbleHorizontalPadding
        guard maxCenter > minCenter else { return containerSize.width / 2 }
        return min(maxCenter, max(minCenter, targetX))
    }

    /// Up/down pointer, nudged horizontally toward the target relative to the
    /// (possibly shifted) bubble center.
    private func verticalArrow(_ dir: ArrowDirection) -> some View {
        let targetX = spotlight?.midX ?? containerSize.width / 2
        let rawOffset = targetX - verticalBubbleCenterX
        let limit = (bubbleWidth / 2) - 24
        let offset = max(-limit, min(limit, rawOffset))
        return ArrowTriangle(direction: dir)
            .fill(DS.ColorToken.surface)
            .frame(width: 22, height: 11)
            .offset(x: offset)
    }

    private func bubbleCard(maxHeight: CGFloat) -> some View {
        let bodyMaxHeight = max(72, maxHeight - bubbleChromeHeightEstimate)

        return VStack(alignment: .leading, spacing: isCompactViewport ? 8 : 10) {
            HStack(spacing: 8) {
                Label(step.lesson.title, systemImage: step.lesson.icon)
                    .font(.caption2.weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(DS.ColorToken.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .layoutPriority(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(DS.ColorToken.primary.opacity(0.12), in: Capsule())
                Spacer(minLength: 8)
                Text("\(controller.stepNumber) / \(controller.stepCount)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            ViewThatFits(in: .vertical) {
                bubbleBody

                ScrollView {
                    bubbleBody
                }
                .scrollIndicators(.visible)
                .frame(maxHeight: bodyMaxHeight)
            }

            footerControls
                .padding(.top, 2)
        }
        .padding(bubbleCardPadding)
        .frame(maxWidth: bubbleWidth, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
        .background(DS.ColorToken.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.28), radius: 18, x: 0, y: 8)
    }

    @ViewBuilder
    private var footerControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                backButton
                skipButton

                Spacer(minLength: 12)

                footerPrimaryControl
            }

            VStack(alignment: .leading, spacing: 10) {
                footerPrimaryControl
                HStack(spacing: 18) {
                    backButton
                    skipButton
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Step backward so a user who advanced too fast can re-read the prior stop.
    /// Shown on every step that has a predecessor — including the "tap the
    /// highlighted control" steps, where it's otherwise the only way back.
    @ViewBuilder
    private var backButton: some View {
        if controller.canGoBack {
            Button {
                controller.goBack()
            } label: {
                Label(AppLocalization.localized("tour.back", value: "Back"), systemImage: "chevron.left")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
            }
            .foregroundStyle(DS.ColorToken.primary)
            .buttonStyle(.plain)
            .accessibilityIdentifier("walkthrough.back")
        }
    }

    private var skipButton: some View {
        Button(AppLocalization.localized("tour.skip", value: "Skip tour")) {
            controller.skip()
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var footerPrimaryControl: some View {
        if step.requiresTargetAction {
            Label(AppLocalization.localized("tour.tap_highlighted", value: "Tap highlighted button"), systemImage: "hand.tap.fill")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .foregroundStyle(DS.ColorToken.primary)
                .padding(.horizontal, isCompactViewport ? 12 : 14)
                .padding(.vertical, isCompactViewport ? 8 : 9)
                .background(DS.ColorToken.primary.opacity(0.12), in: Capsule())
        } else {
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
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(DS.ColorToken.primary)
                .foregroundStyle(.white)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var bubbleBody: some View {
        VStack(alignment: .leading, spacing: isCompactViewport ? 8 : 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: step.icon)
                    .font(.headline)
                    .foregroundStyle(DS.ColorToken.primary)
                    .frame(width: 24)
                Text(step.title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(step.directive)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DS.ColorToken.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(step.purpose)
                .font(isCompactViewport ? .footnote : .callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let coachTip = step.coachTip {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(DS.ColorToken.primary)
                        .font(.caption)
                        .padding(.top, 1)
                    Text(coachTip)
                        .font(isCompactViewport ? .caption2 : .caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(isCompactViewport ? 9 : 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DS.ColorToken.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Completion celebration

/// A celebratory confetti burst shown for a couple of seconds when the user
/// FINISHES the guided tour (skipping stays quiet). Purely decorative and
/// non-interactive; the falling animation is skipped under Reduce Motion, which
/// leaves just the "You're all set!" capsule.
struct WalkthroughCelebrationView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bannerIn = false
    private let pieceCount = 46

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if !reduceMotion {
                    ForEach(0..<pieceCount, id: \.self) { _ in
                        WalkthroughConfettiBit(bounds: proxy.size)
                    }
                }
            }
        }
        .ignoresSafeArea()
        .overlay(alignment: .top) {
            Label(
                AppLocalization.localized("onboarding.finish.title", value: "You're all set!"),
                systemImage: "checkmark.seal.fill"
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(DS.ColorToken.primary, in: Capsule())
            .shadow(color: .black.opacity(0.28), radius: 14, x: 0, y: 6)
            .padding(.top, 12)
            .offset(y: bannerIn ? 0 : -96)
            .opacity(bannerIn ? 1 : 0)
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { bannerIn = true }
            }
        }
        .allowsHitTesting(false)
    }
}

/// One falling confetti rectangle. Random visual parameters are captured once in
/// `@State` defaults so re-renders don't reshuffle them mid-flight.
private struct WalkthroughConfettiBit: View {
    let bounds: CGSize

    @State private var color: Color = [.blue, .purple, .pink, .orange, .yellow, .green, .red, .mint, .cyan].randomElement() ?? .blue
    @State private var startXFraction: CGFloat = .random(in: 0.02...0.98)
    @State private var size: CGFloat = .random(in: 6...11)
    @State private var drift: CGFloat = .random(in: -80...80)
    @State private var spin: Double = .random(in: 160...920)
    @State private var duration: Double = .random(in: 1.5...2.4)
    @State private var delay: Double = .random(in: 0...0.55)
    @State private var animate = false

    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(color)
            .frame(width: size, height: size * 1.5)
            .rotationEffect(.degrees(animate ? spin : 0))
            .position(
                x: bounds.width * startXFraction + (animate ? drift : 0),
                y: animate ? bounds.height + 60 : -60
            )
            .opacity(animate ? 0 : 1)
            .onAppear {
                withAnimation(.easeIn(duration: duration).delay(delay)) { animate = true }
            }
    }
}
