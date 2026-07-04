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

    let client: Client
    let scale: Scale

    @State private var bouncePhase = false
    @State private var sparkleSeed = 0
    @State private var showSparkles = false

    init(client: Client, scale: Scale = .prominent) {
        self.client = client
        self.scale = scale
    }

    var body: some View {
        ZStack(alignment: .top) {
            badgeContent
                .scaleEffect(bouncePhase ? 1.055 : 1)
                .animation(.interpolatingSpring(stiffness: 260, damping: 13), value: bouncePhase)

            if showSparkles {
                LoyaltySparkleBurst(seed: sparkleSeed, scale: scale)
                    .offset(y: -6)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(client.loyaltyPoints) loyalty points")
        .accessibilityIdentifier("loyaltyPointsBadge")
        .onChange(of: client.loyaltyPoints) { oldValue, newValue in
            triggerAnimation(pointsWereAdded: newValue > oldValue)
        }
    }

    private var badgeContent: some View {
        HStack(spacing: scale == .compact ? 5 : 9) {
            Image(systemName: "pawprint.fill")
                .font(.system(size: scale.iconSize, weight: .bold))
                .symbolRenderingMode(.hierarchical)

            VStack(alignment: scale == .compact ? .center : .trailing, spacing: scale == .compact ? 0 : -1) {
                Text("\(client.loyaltyPoints)")
                    .font(scale.pointsFont)
                    .contentTransition(.numericText())
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
                .fill(DS.ColorToken.warning.gradient)
                .shadow(color: DS.ColorToken.warning.opacity(0.24), radius: scale == .compact ? 4 : 10, y: scale == .compact ? 2 : 5)
        )
        .overlay {
            RoundedRectangle(cornerRadius: scale.cornerRadius, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
    }

    private func triggerAnimation(pointsWereAdded: Bool) {
        withAnimation(.interpolatingSpring(stiffness: 300, damping: 12)) {
            bouncePhase = true
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(140))
            withAnimation(.interpolatingSpring(stiffness: 300, damping: 18)) {
                bouncePhase = false
            }
        }

        guard pointsWereAdded else { return }
        sparkleSeed &+= 1
        withAnimation(.easeOut(duration: 0.08)) {
            showSparkles = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(590))
            withAnimation(.easeOut(duration: 0.12)) {
                showSparkles = false
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
            expanded = false
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
