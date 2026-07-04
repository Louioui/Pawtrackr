import SwiftUI

@MainActor
struct LoyaltyPointsBadge: View {
    enum Scale: Equatable {
        case compact
        case prominent

        var horizontalPadding: CGFloat {
            switch self {
            case .compact:
                9
            case .prominent:
                16
            }
        }

        var verticalPadding: CGFloat {
            switch self {
            case .compact:
                5
            case .prominent:
                12
            }
        }

        var iconSize: CGFloat {
            switch self {
            case .compact:
                12
            case .prominent:
                18
            }
        }

        var pointsFont: Font {
            switch self {
            case .compact:
                .caption.weight(.bold)
            case .prominent:
                .system(.largeTitle, design: .rounded).weight(.black)
            }
        }

        var labelFont: Font {
            switch self {
            case .compact:
                .caption2.weight(.semibold)
            case .prominent:
                .caption.weight(.semibold)
            }
        }

        var deltaFont: Font {
            switch self {
            case .compact:
                .caption2.weight(.heavy)
            case .prominent:
                .callout.weight(.heavy)
            }
        }

        var cornerRadius: CGFloat {
            switch self {
            case .compact:
                999
            case .prominent:
                18
            }
        }

        var sparkleSpread: CGFloat {
            switch self {
            case .compact:
                62
            case .prominent:
                112
            }
        }

        var sparkleRise: CGFloat {
            switch self {
            case .compact:
                36
            case .prominent:
                62
            }
        }

        var particleSize: CGFloat {
            switch self {
            case .compact:
                4
            case .prominent:
                6
            }
        }
    }

    /// One points change event. Identity (`id`) is unique per event so the
    /// floating delta chip and sparkle burst get FRESH view identity each
    /// time — a second rapid event replaces them instead of silently
    /// updating views mid-animation.
    private struct DeltaEvent: Equatable {
        let id: Int
        let amount: Int
    }

    let client: Client
    let scale: Scale

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var pulseCount = 0
    @State private var deltaEvent: DeltaEvent?
    @State private var showSparkles = false
    /// Sole owner of decoration teardown. Exactly one lives at a time:
    /// every new event cancels the previous task BEFORE mutating any
    /// animation state, so competing sleeps can never fight over it.
    @State private var decorationTask: Task<Void, Never>?

    init(client: Client, scale: Scale = .prominent) {
        self.client = client
        self.scale = scale
    }

    var body: some View {
        ZStack(alignment: .top) {
            badgeContent
                .phaseAnimator([false, true], trigger: pulseCount) { view, bouncing in
                    view.scaleEffect(bouncing ? 1.06 : 1)
                } animation: { bouncing in
                    bouncing
                        ? .interpolatingSpring(stiffness: 300, damping: 12)
                        : .interpolatingSpring(stiffness: 300, damping: 18)
                }

            if showSparkles, let deltaEvent {
                LoyaltySparkleBurst(seed: deltaEvent.id, scale: scale)
                    .id(deltaEvent.id)
                    .offset(y: -6)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            if let deltaEvent {
                deltaChip(for: deltaEvent)
                    .id(deltaEvent.id)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(client.loyaltyPoints) loyalty points, \(tier.displayName) tier")
        .accessibilityIdentifier("loyaltyPointsBadge")
        .onChange(of: client.loyaltyPoints) { oldValue, newValue in
            pointsDidChange(by: newValue - oldValue)
        }
        .onDisappear {
            decorationTask?.cancel()
            decorationTask = nil
        }
    }

    private var tier: LoyaltyTier {
        LoyaltyEngine.tier(forLifetimeEarned: LoyaltyEngine.lifetimeEarnedPoints(for: client))
    }

    private var badgeContent: some View {
        HStack(spacing: scale == .compact ? 5 : 9) {
            Image(systemName: tier.systemImage)
                .font(.system(size: scale.iconSize, weight: .bold))
                .symbolRenderingMode(.hierarchical)

            VStack(alignment: scale == .compact ? .center : .trailing, spacing: scale == .compact ? 0 : -1) {
                Text("\(client.loyaltyPoints)")
                    .font(scale.pointsFont)
                    .contentTransition(.numericText(value: Double(client.loyaltyPoints)))
                    .monospacedDigit()
                if scale == .prominent {
                    Text("points")
                        .font(scale.labelFont)
                        .foregroundStyle(.white.opacity(0.78))
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, scale.horizontalPadding)
        .padding(.vertical, scale.verticalPadding)
        .background(
            RoundedRectangle(cornerRadius: scale.cornerRadius, style: .continuous)
                .fill(tier.tint.gradient)
                .shadow(color: tier.tint.opacity(0.24), radius: scale == .compact ? 4 : 10, y: scale == .compact ? 2 : 5)
        )
        .overlay {
            RoundedRectangle(cornerRadius: scale.cornerRadius, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
        // The odometer roll must run even when the mutation arrives without an
        // animation transaction (CheckoutTransactionActor save, CloudKit import).
        .animation(MotionSystem.resolved(MotionSystem.snappy, reduceMotion: reduceMotion), value: client.loyaltyPoints)
    }

    private func deltaChip(for event: DeltaEvent) -> some View {
        let gained = event.amount > 0
        return Text(gained ? "+\(event.amount)" : "\(event.amount)")
            .font(scale.deltaFont)
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, scale == .compact ? 6 : 9)
            .padding(.vertical, scale == .compact ? 2 : 4)
            .background(
                Capsule().fill((gained ? DS.ColorToken.success : DS.ColorToken.danger).gradient)
                    .shadow(color: .black.opacity(0.14), radius: 3, y: 1)
            )
            .offset(y: scale == .compact ? -18 : -26)
            .transition(
                .asymmetric(
                    insertion: .offset(y: 10).combined(with: .scale(scale: 0.6)).combined(with: .opacity),
                    removal: .offset(y: -14).combined(with: .opacity)
                )
            )
    }

    private func pointsDidChange(by delta: Int) {
        guard delta != 0 else { return }
        pulseCount &+= 1

        // Decorations are pure garnish — respect Reduce Motion / thermals and
        // let the numericText roll carry the change on its own.
        guard MotionGovernor.shouldAnimate(reduceMotion: reduceMotion) else { return }

        // Cancel the previous event's teardown FIRST so it can never clobber
        // the state this event is about to own.
        decorationTask?.cancel()

        let event = DeltaEvent(id: (deltaEvent?.id ?? 0) &+ 1, amount: delta)
        withAnimation(MotionSystem.snappy) {
            deltaEvent = event
            showSparkles = delta > 0
        }

        decorationTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(900))
            } catch {
                return // cancelled: a newer event owns the decorations now
            }
            withAnimation(.easeOut(duration: 0.18)) {
                showSparkles = false
                deltaEvent = nil
            }
        }
    }
}

private struct LoyaltySparkleBurst: View {
    let seed: Int
    let scale: LoyaltyPointsBadge.Scale

    @State private var expanded = false

    var body: some View {
        ZStack {
            ForEach(0..<10, id: \.self) { index in
                sparkle(index: index)
            }
        }
        .frame(width: scale.sparkleSpread, height: scale.sparkleRise)
        .onAppear {
            withAnimation(.easeOut(duration: 0.56)) {
                expanded = true
            }
        }
    }

    private func sparkle(index: Int) -> some View {
        let spreadUnit = CGFloat(index) / 9 - 0.5
        let seededOffset = CGFloat((seed + index * 3) % 5 - 2) * 3
        let x = spreadUnit * scale.sparkleSpread + seededOffset
        let verticalWave = CGFloat((index * 7 + seed) % 6) / 10
        let y = -scale.sparkleRise * (0.52 + verticalWave)
        let size = scale.particleSize + CGFloat(index % 3)

        return RoundedRectangle(cornerRadius: size / 2, style: .continuous)
            .fill(index.isMultiple(of: 2) ? Color.white : DS.ColorToken.warning)
            .frame(width: size, height: size)
            .rotationEffect(.degrees(expanded ? Double(index * 18 + 40) : Double(index * 6)))
            .offset(x: expanded ? x : 0, y: expanded ? y : 0)
            .opacity(expanded ? 0 : 0.95)
            .scaleEffect(expanded ? 0.4 : 1)
            .blur(radius: expanded ? 0.8 : 0)
    }
}
