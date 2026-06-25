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

enum WalkthroughTargetFrame {
    /// Returns a visible, non-trivial target rect in the overlay's local
    /// coordinate space, or nil when SwiftUI handed us a stale/offscreen anchor.
    /// iPad split view and Stage Manager can temporarily report anchors from a
    /// transitioning host; dropping them lets the tour fall back to a centered
    /// bubble instead of drawing a misleading spotlight.
    static func validated(_ rect: CGRect?, in containerSize: CGSize, safeAreaInsets: EdgeInsets) -> CGRect? {
        guard var rect, rect.isFinite, rect.width >= 2, rect.height >= 2,
              containerSize.width >= 2, containerSize.height >= 2
        else { return nil }

        let visibleBounds = CGRect(
            x: max(0, safeAreaInsets.leading) + 8,
            y: max(0, safeAreaInsets.top) + 8,
            width: max(1, containerSize.width - max(0, safeAreaInsets.leading) - max(0, safeAreaInsets.trailing) - 16),
            height: max(1, containerSize.height - max(0, safeAreaInsets.top) - max(0, safeAreaInsets.bottom) - 16)
        )

        rect = rect.standardized
        let intersection = rect.intersection(visibleBounds)
        guard !intersection.isNull, !intersection.isEmpty,
              intersection.width >= 2, intersection.height >= 2
        else { return nil }

        return intersection
    }
}

private extension CGRect {
    var isFinite: Bool {
        [origin.x, origin.y, size.width, size.height].allSatisfy(\.isFinite)
    }
}

enum WalkthroughOverlayLayout {
    enum Placement: Equatable {
        case below
        case above
        case trailing
        case leading
        case center
    }

    enum ArrowDirection: Equatable {
        case up
        case down
        case left
        case right
    }

    struct Result: Equatable {
        let spotlight: CGRect?
        let bubbleFrame: CGRect
        let cardWidth: CGFloat
        let cardMaxHeight: CGFloat
        let placement: Placement
        let arrowDirection: ArrowDirection?
        let arrowOffset: CGFloat
        let isCompactViewport: Bool
    }

    private struct Metrics {
        let containerSize: CGSize
        let safeAreaInsets: EdgeInsets

        var isCompactViewport: Bool {
            containerSize.width < 430 || containerSize.height < 760
        }

        var bubbleMaxWidth: CGFloat {
            if containerSize.width >= 900 { return 520 }
            if containerSize.width >= 620 { return 480 }
            return 370
        }

        var horizontalPadding: CGFloat {
            isCompactViewport ? 16 : 20
        }

        var cardWidth: CGFloat {
            min(bubbleMaxWidth, max(260, containerSize.width - horizontalPadding * 2))
        }

        var bubbleMinHeight: CGFloat {
            isCompactViewport ? 150 : 164
        }

        var safeTopPadding: CGFloat {
            max(safeAreaInsets.top + 8, 16)
        }

        var safeBottomPadding: CGFloat {
            max(safeAreaInsets.bottom + 8, 16)
        }

        var readableBubbleMaxHeight: CGFloat {
            min(isCompactViewport ? 300 : 348, max(220, containerSize.height - safeTopPadding - safeBottomPadding - 20))
        }
    }

    private static let spotlightPadding: CGFloat = 10
    private static let bubbleGap: CGFloat = 16
    private static let compactBubbleGap: CGFloat = 10
    private static let arrowExtent: CGFloat = 11
    private static let trailingGap: CGFloat = 12
    private static let minimumSideBubbleWidth: CGFloat = 260

    static func layout(
        step: WalkthroughStep,
        targetRect: CGRect?,
        containerSize: CGSize,
        safeAreaInsets: EdgeInsets
    ) -> Result {
        let metrics = Metrics(containerSize: containerSize, safeAreaInsets: safeAreaInsets)
        let gap = metrics.isCompactViewport ? compactBubbleGap : bubbleGap
        let spotlight = spotlightRect(for: targetRect, metrics: metrics)
        guard let spotlight else {
            let height = boundedCardHeight(
                availableHeight: containerSize.height - metrics.safeTopPadding - metrics.safeBottomPadding,
                metrics: metrics
            )
            let frame = CGRect(
                x: (containerSize.width - metrics.cardWidth) / 2,
                y: (containerSize.height - height) / 2,
                width: metrics.cardWidth,
                height: height
            ).clamped(to: safeBounds(metrics: metrics))
            return Result(
                spotlight: nil,
                bubbleFrame: frame,
                cardWidth: metrics.cardWidth,
                cardMaxHeight: frame.height,
                placement: .center,
                arrowDirection: nil,
                arrowOffset: 0,
                isCompactViewport: metrics.isCompactViewport
            )
        }

        let placement = choosePlacement(for: step, spotlight: spotlight, metrics: metrics, gap: gap)
        let preferred = result(for: placement, spotlight: spotlight, metrics: metrics, gap: gap)
        if !preferred.bubbleFrame.intersects(spotlight) {
            return preferred
        }

        for fallbackPlacement in fallbackPlacements(after: placement, spotlight: spotlight, metrics: metrics, gap: gap) {
            let fallback = result(for: fallbackPlacement, spotlight: spotlight, metrics: metrics, gap: gap)
            if !fallback.bubbleFrame.intersects(spotlight) {
                return fallback
            }
        }

        return preferred
    }

    private static func spotlightRect(for targetRect: CGRect?, metrics: Metrics) -> CGRect? {
        guard let targetRect, targetRect.width > 0, targetRect.height > 0 else { return nil }
        let padded = targetRect.insetBy(dx: -spotlightPadding, dy: -spotlightPadding)
        let bounds = CGRect(
            x: max(6, metrics.safeAreaInsets.leading + 6),
            y: max(6, metrics.safeAreaInsets.top + 6),
            width: max(1, metrics.containerSize.width - metrics.safeAreaInsets.leading - metrics.safeAreaInsets.trailing - 12),
            height: max(1, metrics.containerSize.height - metrics.safeAreaInsets.top - metrics.safeAreaInsets.bottom - 12)
        )
        let clamped = padded.intersection(bounds)
        return clamped.isNull || clamped.isEmpty ? padded : clamped
    }

    private static func choosePlacement(
        for step: WalkthroughStep,
        spotlight: CGRect,
        metrics: Metrics,
        gap: CGFloat
    ) -> Placement {
        let trailingSpace = metrics.containerSize.width - spotlight.maxX - metrics.horizontalPadding
        let leadingSpace = spotlight.minX - metrics.horizontalPadding
        let minimumSideSpace = minimumSideBubbleWidth + arrowExtent + trailingGap
        if metrics.containerSize.width >= 620 {
            if trailingSpace >= minimumSideSpace,
               trailingSpace > leadingSpace {
                return .trailing
            }

            if leadingSpace >= minimumSideSpace,
               leadingSpace >= trailingSpace {
                return .leading
            }
        }

        if spotlight.midY > metrics.containerSize.height * 0.72 { return .above }

        let below = availableBelow(spotlight: spotlight, metrics: metrics, gap: gap)
        let above = availableAbove(spotlight: spotlight, metrics: metrics, gap: gap)
        let preferredMinimum = metrics.bubbleMinHeight

        if below >= preferredMinimum || below >= above {
            return .below
        }
        if above >= preferredMinimum || above > 0 {
            return .above
        }

        // Keep an anchored bubble outside the target even in cramped layouts.
        // The card body can scroll, but the target must remain visible and tappable.
        return below >= above ? .below : .above
    }

    private static func result(
        for placement: Placement,
        spotlight: CGRect,
        metrics: Metrics,
        gap: CGFloat
    ) -> Result {
        switch placement {
        case .below:
            return verticalResult(below: true, spotlight: spotlight, metrics: metrics, gap: gap)
        case .above:
            return verticalResult(below: false, spotlight: spotlight, metrics: metrics, gap: gap)
        case .trailing:
            return trailingResult(spotlight: spotlight, metrics: metrics)
        case .leading:
            return leadingResult(spotlight: spotlight, metrics: metrics)
        case .center:
            let height = boundedCardHeight(
                availableHeight: metrics.containerSize.height - metrics.safeTopPadding - metrics.safeBottomPadding,
                metrics: metrics
            )
            let frame = CGRect(
                x: (metrics.containerSize.width - metrics.cardWidth) / 2,
                y: (metrics.containerSize.height - height) / 2,
                width: metrics.cardWidth,
                height: height
            ).clamped(to: safeBounds(metrics: metrics))
            return Result(
                spotlight: spotlight,
                bubbleFrame: frame,
                cardWidth: metrics.cardWidth,
                cardMaxHeight: frame.height,
                placement: .center,
                arrowDirection: nil,
                arrowOffset: 0,
                isCompactViewport: metrics.isCompactViewport
            )
        }
    }

    private static func fallbackPlacements(
        after placement: Placement,
        spotlight: CGRect,
        metrics: Metrics,
        gap: CGFloat
    ) -> [Placement] {
        var placements: [Placement] = []

        let above = availableAbove(spotlight: spotlight, metrics: metrics, gap: gap)
        let below = availableBelow(spotlight: spotlight, metrics: metrics, gap: gap)
        if placement != .above, above > 0 { placements.append(.above) }
        if placement != .below, below > 0 { placements.append(.below) }

        let trailingSpace = metrics.containerSize.width - spotlight.maxX - metrics.horizontalPadding
        if placement != .trailing,
           metrics.containerSize.width >= 620,
           trailingSpace >= minimumSideBubbleWidth + arrowExtent + trailingGap {
            placements.append(.trailing)
        }

        let leadingSpace = spotlight.minX - metrics.horizontalPadding
        if placement != .leading,
           metrics.containerSize.width >= 620,
           leadingSpace >= minimumSideBubbleWidth + arrowExtent + trailingGap {
            placements.append(.leading)
        }

        return placements
    }

    private static func verticalResult(
        below: Bool,
        spotlight: CGRect,
        metrics: Metrics,
        gap: CGFloat
    ) -> Result {
        let available = below
            ? availableBelow(spotlight: spotlight, metrics: metrics, gap: gap)
            : availableAbove(spotlight: spotlight, metrics: metrics, gap: gap)
        let cardHeight = boundedCardHeight(availableHeight: available, metrics: metrics)
        let totalHeight = cardHeight + arrowExtent
        let centerX = clampedBubbleCenterX(for: spotlight, cardWidth: metrics.cardWidth, metrics: metrics)
        let x = centerX - metrics.cardWidth / 2
        let y = below
            ? spotlight.maxY + gap
            : spotlight.minY - gap - totalHeight
        let frame = CGRect(x: x, y: y, width: metrics.cardWidth, height: totalHeight)
            .clamped(to: safeBounds(metrics: metrics))
        let rawOffset = spotlight.midX - frame.midX
        let limit = (metrics.cardWidth / 2) - 24
        let arrowOffset = max(-limit, min(limit, rawOffset))

        return Result(
            spotlight: spotlight,
            bubbleFrame: frame,
            cardWidth: metrics.cardWidth,
            cardMaxHeight: min(cardHeight, frame.height - arrowExtent),
            placement: below ? .below : .above,
            arrowDirection: below ? .up : .down,
            arrowOffset: arrowOffset,
            isCompactViewport: metrics.isCompactViewport
        )
    }

    private static func trailingResult(spotlight: CGRect, metrics: Metrics) -> Result {
        let safe = safeBounds(metrics: metrics)
        let x = min(spotlight.maxX + trailingGap, metrics.containerSize.width * 0.55)
        let availableWidth = max(260, safe.maxX - x)
        let outerWidth = min(metrics.cardWidth + arrowExtent, availableWidth)
        let cardWidth = max(240, outerWidth - arrowExtent)
        let cardHeight = boundedCardHeight(
            availableHeight: metrics.containerSize.height - metrics.safeTopPadding - metrics.safeBottomPadding,
            metrics: metrics
        )
        let y = max(safe.minY, min(spotlight.minY - 8, safe.maxY - cardHeight))
        let frame = CGRect(x: x, y: y, width: outerWidth, height: cardHeight)
            .clamped(to: safe)

        return Result(
            spotlight: spotlight,
            bubbleFrame: frame,
            cardWidth: cardWidth,
            cardMaxHeight: frame.height,
            placement: .trailing,
            arrowDirection: .left,
            arrowOffset: 16,
            isCompactViewport: metrics.isCompactViewport
        )
    }

    private static func leadingResult(spotlight: CGRect, metrics: Metrics) -> Result {
        let safe = safeBounds(metrics: metrics)
        let availableWidth = max(260, spotlight.minX - safe.minX - trailingGap)
        let outerWidth = min(metrics.cardWidth + arrowExtent, availableWidth)
        let cardWidth = max(240, outerWidth - arrowExtent)
        let x = max(safe.minX, spotlight.minX - trailingGap - outerWidth)
        let cardHeight = boundedCardHeight(
            availableHeight: metrics.containerSize.height - metrics.safeTopPadding - metrics.safeBottomPadding,
            metrics: metrics
        )
        let y = max(safe.minY, min(spotlight.minY - 8, safe.maxY - cardHeight))
        let frame = CGRect(x: x, y: y, width: outerWidth, height: cardHeight)
            .clamped(to: safe)

        return Result(
            spotlight: spotlight,
            bubbleFrame: frame,
            cardWidth: cardWidth,
            cardMaxHeight: frame.height,
            placement: .leading,
            arrowDirection: .right,
            arrowOffset: 16,
            isCompactViewport: metrics.isCompactViewport
        )
    }

    private static func availableAbove(spotlight: CGRect, metrics: Metrics, gap: CGFloat) -> CGFloat {
        spotlight.minY - gap - arrowExtent - metrics.safeTopPadding
    }

    private static func availableBelow(spotlight: CGRect, metrics: Metrics, gap: CGFloat) -> CGFloat {
        metrics.containerSize.height - spotlight.maxY - gap - arrowExtent - metrics.safeBottomPadding
    }

    private static func boundedCardHeight(availableHeight: CGFloat, metrics: Metrics) -> CGFloat {
        min(metrics.readableBubbleMaxHeight, max(96, availableHeight))
    }

    private static func clampedBubbleCenterX(for spotlight: CGRect, cardWidth: CGFloat, metrics: Metrics) -> CGFloat {
        let halfWidth = cardWidth / 2
        let minCenter = halfWidth + metrics.horizontalPadding
        let maxCenter = metrics.containerSize.width - halfWidth - metrics.horizontalPadding
        guard maxCenter > minCenter else { return metrics.containerSize.width / 2 }
        return min(maxCenter, max(minCenter, spotlight.midX))
    }

    private static func safeBounds(metrics: Metrics) -> CGRect {
        CGRect(
            x: max(0, metrics.safeAreaInsets.leading) + 8,
            y: max(0, metrics.safeAreaInsets.top) + 8,
            width: max(1, metrics.containerSize.width - max(0, metrics.safeAreaInsets.leading) - max(0, metrics.safeAreaInsets.trailing) - 16),
            height: max(1, metrics.containerSize.height - max(0, metrics.safeAreaInsets.top) - max(0, metrics.safeAreaInsets.bottom) - 16)
        )
    }
}

private extension CGRect {
    func clamped(to bounds: CGRect) -> CGRect {
        let width = min(self.width, bounds.width)
        let height = min(self.height, bounds.height)
        let x = min(max(self.minX, bounds.minX), bounds.maxX - width)
        let y = min(max(self.minY, bounds.minY), bounds.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

/// Which slice of the tour an overlay is responsible for. On iPhone (and iPad
/// split-screen compact) one overlay owns everything. On a `NavigationSplitView`
/// (iPad regular / Mac) the sidebar and detail are separate hosting contexts, and
/// a single root overlay resolves DETAIL-column anchors without the sidebar's
/// horizontal offset — so the spotlight spans the whole window instead of framing
/// the element. Splitting the work fixes that: the root overlay handles the
/// sidebar nav rows (which it CAN resolve), and an overlay hosted inside the
/// detail column handles content steps (whose anchors resolve tightly there).
enum WalkthroughOverlayScope {
    case all           // single overlay owns every step (iPhone / compact)
    case navigation    // only the primary sidebar nav-row steps
    case content       // everything except the primary nav rows
    case rootContent   // content in a column ROOT view (dashboard / insights) — NOT a pushed detail
    case detailContent // content whose anchors live in a PUSHED detail view

    private static let navigationAnchors: Set<WalkthroughAnchorID> = [
        .dashboard, .clients, .insights, .settings
    ]

    /// Anchors that live inside a PUSHED `NavigationStack` destination
    /// (`ClientDetailView`, `CheckoutView`, `SettingsDetailView`). On iPad / macOS
    /// these are drawn by an overlay re-hosted ON the pushed view, because the
    /// split-view detail-column overlay sits OUTSIDE the `NavigationStack` and
    /// can't resolve them. Excluding them from the detail-column overlay
    /// (`.rootContent`) stops a SECOND overlay from drawing a stray spotlight and
    /// double-dimming the real target (which left e.g. the Add Pet button un-lit
    /// with a faint stray circle elsewhere).
    private static let detailAnchors: Set<WalkthroughAnchorID> = [
        .cdOwner, .cdEmergency, .cdPets, .cdAddPet, .cdCheckIn, .cdCheckOut, .cdPetHistory, .cdHistory,
        .coServices, .coDetails, .coPayment, .coReview, .coConfirm,
        .setBusiness, .setSecurity, .setData, .setICloud, .setAbout, .setStartFresh
    ]

    func handles(_ step: WalkthroughStep) -> Bool {
        switch self {
        case .all: return true
        case .navigation: return Self.navigationAnchors.contains(step.anchor)
        case .content: return !Self.navigationAnchors.contains(step.anchor)
        case .rootContent:
            return !Self.navigationAnchors.contains(step.anchor) && !Self.detailAnchors.contains(step.anchor)
        case .detailContent:
            return Self.detailAnchors.contains(step.anchor)
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
        WalkthroughOverlayHost(
            content: self,
            controller: controller,
            presenting: presenting,
            scope: scope
        )
    }
}

private struct WalkthroughOverlayHost<Content: View>: View {
    let content: Content
    let controller: WalkthroughController
    let presenting: WalkthroughPresentation?
    let scope: WalkthroughOverlayScope

    @State private var frames: [WalkthroughAnchorID: CGRect] = [:]

    var body: some View {
        content
            .coordinateSpace(name: WalkthroughFramePreferenceKey.coordinateSpaceName)
            .onPreferenceChange(WalkthroughFramePreferenceKey.self) { frames = $0 }
            .overlayPreferenceValue(WalkthroughAnchorPreferenceKey.self) { anchors in
                GeometryReader { proxy in
                    if controller.isActive, let step = controller.currentStep,
                       step.presents == presenting, scope.handles(step) {
                        // Prefer the live viewport frame, then the live anchor,
                        // then a computed fallback for targets SwiftUI won't expose.
                        let rawFrameTarget = frames[step.anchor]
                        let rawAnchorTarget = anchors[step.anchor].map { proxy[$0] }
                        let rawLiveTarget = rawAnchorTarget ?? rawFrameTarget
                        let liveTarget = WalkthroughTargetFrame.validated(
                            rawLiveTarget,
                            in: proxy.size,
                            safeAreaInsets: proxy.safeAreaInsets
                        )
                        let fallbackTarget = WalkthroughTargetFrame.validated(
                            walkthroughFallbackRect(step.fallback, in: proxy),
                            in: proxy.size,
                            safeAreaInsets: proxy.safeAreaInsets
                        )
                        let target = liveTarget ?? fallbackTarget
                        WalkthroughOverlayView(
                            step: step,
                            rawTargetRect: rawLiveTarget,
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

/// An isosceles triangle pointing in one of four directions — the bubble's
/// pointer into the spotlight.
private struct ArrowTriangle: Shape {
    var direction: WalkthroughOverlayLayout.ArrowDirection
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

private struct WalkthroughOverlayView: View {
    let step: WalkthroughStep
    let rawTargetRect: CGRect?
    let targetRect: CGRect?
    let containerSize: CGSize
    let containerInsets: EdgeInsets
    let controller: WalkthroughController

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Gentle, continuous "breathing" of the spotlight ring to draw the eye to
    /// the highlighted control. Disabled under Reduce Motion.
    @State private var ringPulse = false

    private var dimOpacity: Double {
        #if os(macOS)
        return 0.58
        #else
        return isCompactViewport ? 0.62 : 0.54
        #endif
    }

    private var layout: WalkthroughOverlayLayout.Result {
        WalkthroughOverlayLayout.layout(
            step: step,
            targetRect: targetRect,
            containerSize: containerSize,
            safeAreaInsets: containerInsets
        )
    }

    private var spotlight: CGRect? {
        layout.spotlight
    }

    private var isCompactViewport: Bool {
        layout.isCompactViewport
    }

    private var bubbleWidth: CGFloat {
        layout.cardWidth
    }

    private var bubbleCardPadding: CGFloat {
        isCompactViewport ? 13 : 16
    }

    private var bubbleChromeHeightEstimate: CGFloat {
        isCompactViewport ? 124 : 140
    }

    private var placement: WalkthroughOverlayLayout.Placement {
        layout.placement
    }

    var body: some View {
        ZStack {
            dimLayer
            spotlightRing
            spotlightTapTarget
            bubble
            accessibilityProbe
            activeAnchorProbe
        }
        // Interpolate the spotlight + bubble both when the step changes and when
        // the target frame moves (e.g. a macOS window resize mid-tour).
        .motionAnimation(MotionSystem.fluid, value: step.id)
            .motionAnimation(MotionSystem.fluid, value: targetRect)
    }

    private var accessibilityProbe: some View {
        Color.clear
            .frame(width: 2, height: 2)
            .position(x: 1, y: 1)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("walkthrough.card")
            .accessibilityLabel(Text(step.title))
            .accessibilityValue(Text("\(controller.stepNumber) of \(controller.stepCount)"))
    }

    private var activeAnchorProbe: some View {
        Color.clear
            .frame(width: 2, height: 2)
            .position(x: 3, y: 3)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("walkthrough.activeAnchor.\(step.anchor.rawValue)")
            .accessibilityLabel(Text(step.anchor.rawValue))
            .accessibilityValue(Text(layoutDebugValue))
    }

    private var layoutDebugValue: String {
        [
            "placement=\(placement)",
            "raw=\(debugDescription(for: rawTargetRect))",
            "target=\(debugDescription(for: targetRect))",
            "spotlight=\(debugDescription(for: spotlight))",
            "bubble=\(debugDescription(for: layout.bubbleFrame))",
            "container=\(Int(containerSize.width.rounded()))x\(Int(containerSize.height.rounded()))"
        ].joined(separator: ";")
    }

    private func debugDescription(for rect: CGRect?) -> String {
        guard let rect else { return "nil" }
        return debugDescription(for: rect)
    }

    private func debugDescription(for rect: CGRect) -> String {
        let values = [rect.minX, rect.minY, rect.width, rect.height]
            .map { Int($0.rounded()).description }
            .joined(separator: ",")
        return "[\(values)]"
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
                guard MotionGovernor.shouldAnimate(reduceMotion: reduceMotion) else { return }
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
        case .leading: leadingBubble
        case .center: centerBubble
        }
    }

    /// Bubble above or below the spotlight (tab bar / general case).
    private func verticalBubble(below: Bool) -> some View {
        let result = layout

        return VStack(spacing: 0) {
            if below { verticalArrow(.up) }
            bubbleCard(maxHeight: result.cardMaxHeight)
                .frame(maxHeight: result.cardMaxHeight, alignment: .top)
            if !below { verticalArrow(.down) }
        }
        .frame(width: result.bubbleFrame.width, height: result.bubbleFrame.height, alignment: below ? .top : .bottom)
        .position(x: result.bubbleFrame.midX, y: result.bubbleFrame.midY)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    /// Bubble to the leading side of a right-side target, like iPad pet actions.
    private var leadingBubble: some View {
        let result = layout

        return HStack(alignment: .top, spacing: 0) {
            bubbleCard(maxHeight: result.cardMaxHeight)
                .frame(maxHeight: result.cardMaxHeight, alignment: .top)
            ArrowTriangle(direction: .right)
                .fill(DS.ColorToken.surface)
                .frame(width: 11, height: 22)
                .padding(.top, result.arrowOffset)
        }
        .frame(width: result.bubbleFrame.width, height: result.bubbleFrame.height, alignment: .topLeading)
        .position(x: result.bubbleFrame.midX, y: result.bubbleFrame.midY)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    /// Bubble to the trailing side of the spotlight (sidebar row on Mac/iPad).
    private var trailingBubble: some View {
        let result = layout

        return HStack(alignment: .top, spacing: 0) {
            ArrowTriangle(direction: .left)
                .fill(DS.ColorToken.surface)
                .frame(width: 11, height: 22)
                .padding(.top, result.arrowOffset)
            bubbleCard(maxHeight: result.cardMaxHeight)
                .frame(maxHeight: result.cardMaxHeight, alignment: .top)
        }
        .frame(width: result.bubbleFrame.width, height: result.bubbleFrame.height, alignment: .topLeading)
        .position(x: result.bubbleFrame.midX, y: result.bubbleFrame.midY)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    /// Centered fallback when a step is informational or the target hasn't
    /// appeared yet. This keeps the tour readable instead of silently dropping
    /// the bubble.
    private var centerBubble: some View {
        let result = layout
        return bubbleCard(maxHeight: result.cardMaxHeight)
            .frame(width: result.bubbleFrame.width, height: result.bubbleFrame.height, alignment: .center)
            .position(x: result.bubbleFrame.midX, y: result.bubbleFrame.midY)
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    /// Up/down pointer, nudged horizontally toward the target relative to the
    /// (possibly shifted) bubble center.
    private func verticalArrow(_ dir: WalkthroughOverlayLayout.ArrowDirection) -> some View {
        return ArrowTriangle(direction: dir)
            .fill(DS.ColorToken.surface)
            .frame(width: 22, height: 11)
            .offset(x: layout.arrowOffset)
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
                    .accessibilityIdentifier("walkthrough.stepCounter")
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
        .frame(width: bubbleWidth, alignment: .top)
        .frame(maxHeight: maxHeight, alignment: .top)
        .background(DS.ColorToken.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.28), radius: 18, x: 0, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("walkthrough.bubble")
        .accessibilityLabel(Text(step.title))
        .accessibilityValue(Text("\(controller.stepNumber) of \(controller.stepCount)"))
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
        .accessibilityIdentifier("walkthrough.skip")
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
                .accessibilityIdentifier("walkthrough.tapHighlighted")
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
            .pressScaleStyle(hapticsEnabled: true)
            .accessibilityIdentifier("walkthrough.primary")
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
