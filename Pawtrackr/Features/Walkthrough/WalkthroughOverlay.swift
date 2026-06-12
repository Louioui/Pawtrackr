//
//  WalkthroughOverlay.swift
//  Pawtrackr
//
//  The visual layer of the guided tour: dims the screen, cuts a glowing hole
//  around the current step's control, points an arrow at it, and floats a bubble
//  explaining what to do and why it helps. Touches are blocked except on the
//  spotlight and the bubble's own buttons.
//

import SwiftUI

extension View {
    /// Hosts the guided-tour overlay above this view's content. Anchors registered
    /// with `.walkthroughAnchor(_:)` anywhere in the subtree are resolved here, so
    /// attach this at the screen root that contains the tour's target controls.
    func walkthroughOverlay(_ controller: WalkthroughController) -> some View {
        overlayPreferenceValue(WalkthroughAnchorPreferenceKey.self) { anchors in
            GeometryReader { proxy in
                if controller.isActive, let step = controller.currentStep {
                    let targetRect = anchors[step.anchor].map { proxy[$0] }
                    WalkthroughOverlayView(
                        step: step,
                        targetRect: targetRect,
                        containerSize: proxy.size,
                        controller: controller
                    )
                }
            }
            .ignoresSafeArea()
        }
    }
}

/// A simple isosceles triangle used as the bubble's pointer.
private struct PointerTriangle: Shape {
    /// When true the apex points up (bubble sits below the target).
    var pointsUp: Bool
    func path(in rect: CGRect) -> Path {
        var p = Path()
        if pointsUp {
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        } else {
            p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        }
        p.closeSubpath()
        return p
    }
}

private struct WalkthroughOverlayView: View {
    let step: WalkthroughStep
    let targetRect: CGRect?
    let containerSize: CGSize
    let controller: WalkthroughController

    private let dimOpacity = 0.72
    private let spotlightPadding: CGFloat = 10
    private let bubbleMaxWidth: CGFloat = 460

    /// Inflated rect we actually cut/ring around the target.
    private var spotlight: CGRect? {
        guard let r = targetRect, r.width > 0, r.height > 0 else { return nil }
        return r.insetBy(dx: -spotlightPadding, dy: -spotlightPadding)
    }

    /// Place the bubble in the half of the screen opposite the target so it never
    /// overlaps the control. Defaults to lower-half placement when unmeasured.
    private var bubbleBelowTarget: Bool {
        (spotlight?.midY ?? containerSize.height / 2) < containerSize.height * 0.5
    }

    var body: some View {
        ZStack {
            dimLayer
            spotlightRing
            spotlightTapTarget
            bubble
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: step.id)
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
        .onTapGesture { /* swallow taps on the dimmed area so the app can't be touched */ }
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

    private var bubble: some View {
        let below = bubbleBelowTarget
        let gap: CGFloat = 16
        let topInset = below ? min((spotlight?.maxY ?? 0) + gap, containerSize.height * 0.62) : 0
        let bottomInset = below ? 0 : min(containerSize.height - (spotlight?.minY ?? containerSize.height) + gap, containerSize.height * 0.62)

        return VStack(spacing: 0) {
            if below { arrow(pointsUp: true) }
            bubbleCard
            if !below { arrow(pointsUp: false) }
        }
        .frame(maxWidth: bubbleMaxWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: below ? .top : .bottom)
        .padding(.horizontal, 20)
        .padding(.top, topInset)
        .padding(.bottom, bottomInset)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    /// Pointer triangle, nudged horizontally toward the target's center.
    private func arrow(pointsUp: Bool) -> some View {
        let targetX = spotlight?.midX ?? containerSize.width / 2
        let rawOffset = targetX - containerSize.width / 2
        let limit = (min(bubbleMaxWidth, containerSize.width - 40) / 2) - 24
        let offset = max(-limit, min(limit, rawOffset))
        return PointerTriangle(pointsUp: pointsUp)
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
                Button(NSLocalizedString("tour.skip", value: "Skip tour", comment: "")) {
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
                             ? NSLocalizedString("tour.done", value: "Done", comment: "")
                             : NSLocalizedString("tour.next", value: "Next", comment: ""))
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
