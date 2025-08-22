//
//  FAB.swift
//  Pawtrackr
//
//  Reusable Floating Action Button
//  - Blue gradient circular button with shadow
//  - Default system image: plus
//  - Haptic tap
//  - "fabOverlay" modifier to pin it bottom‑trailing over any content
//
//  Created by mac on 8/14/25.
//  Updated by mac on 8/16/25.
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

public struct FAB: View {
    public var diameter: CGFloat = 56
    public var systemImage: String = "plus"
    public var accessibilityLabel: String = "Add New"
    public var enableHaptics: Bool = true
    public var isLoading: Bool = false
    public var action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public enum Size {
        case small, regular, large
        var diameter: CGFloat {
            switch self { case .small: return 44; case .regular: return 56; case .large: return 64 }
        }
    }

    public enum Style {
        case primary, secondary, destructive
    }

    public var size: Size = .regular
    public var style: Style = .primary
    public var tint: Color = .accentColor

    private var effectiveDiameter: CGFloat {
        // Respect custom diameter if the caller changed it; otherwise use size preset
        (diameter != 56) ? diameter : size.diameter
    }

    private var backgroundColor: Color {
        switch style {
        case .primary: return tint
        case .secondary: return tint.opacity(0.9)
        case .destructive: return Color.red
        }
    }

    public init(
        diameter: CGFloat = 56,
        systemImage: String = "plus",
        accessibilityLabel: String = "Add New",
        enableHaptics: Bool = true,
        isLoading: Bool = false,
        size: Size = .regular,
        style: Style = .primary,
        tint: Color = .accentColor,
        action: @escaping () -> Void
    ) {
        self.diameter = diameter
        self.systemImage = systemImage
        self.accessibilityLabel = accessibilityLabel
        self.enableHaptics = enableHaptics
        self.isLoading = isLoading
        self.size = size
        self.style = style
        self.tint = tint
        self.action = action
    }

    public var body: some View {
        Button(action: tap) {
            ZStack {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .frame(width: effectiveDiameter, height: effectiveDiameter)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 24, weight: .bold))
                        .frame(width: effectiveDiameter, height: effectiveDiameter)
                }
            }
            .frame(width: effectiveDiameter, height: effectiveDiameter)
            .background(Circle().fill(backgroundColor))
            .foregroundColor(.white)
            .shadow(color: .black.opacity(0.2), radius: 5, x: 0, y: 4)
            .contentShape(Circle())
            .accessibilityLabel(Text(accessibilityLabel))
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(Text("Primary action"))
            .keyboardShortcut(.defaultAction)
        }
        .buttonStyle(PressedScaleStyle())
        .onHover { hovering in
            if reduceMotion {
                isHovering = hovering
            } else {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isHovering = hovering
                }
            }
        }
        .scaleEffect(isHovering ? 1.06 : 1.0)
        #if os(iOS)
        .hoverEffect(.lift)
        #endif
    }

    private func tap() {
        guard !isLoading else { return }
        #if os(iOS)
        if enableHaptics {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        #endif
        action()
    }
}

private struct PressedScaleStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

// MARK: - Overlay helper

public struct FABOverlayModifier<FabContent: View>: ViewModifier {
    let alignment: Alignment
    let padding: EdgeInsets
    let padForSafeArea: Bool
    let fab: () -> FabContent

    public init(
        alignment: Alignment = .bottomTrailing,
        padding: EdgeInsets = EdgeInsets(top: 0, leading: 0, bottom: 24, trailing: 24),
        padForSafeArea: Bool = true,
        @ViewBuilder fab: @escaping () -> FabContent
    ) {
        self.alignment = alignment
        self.padding = padding
        self.padForSafeArea = padForSafeArea
        self.fab = fab
    }

    public func body(content: Content) -> some View {
        content.overlay(alignment: alignment) {
            fab()
                .padding(padding)
                .padding(.bottom, padForSafeArea ? max(0, bottomSafeAreaInset() - 4) : 0)
                .ignoresSafeArea(edges: [.bottom])
        }
    }
}

#if os(iOS)
private func bottomSafeAreaInset() -> CGFloat {
    // Best-effort lookup; fine for in-app usage and previews
    return UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap { $0.windows }
        .first(where: { $0.isKeyWindow })?.safeAreaInsets.bottom ?? 0
}
#else
private func bottomSafeAreaInset() -> CGFloat { 0 }
#endif

public extension View {
    /// Pins a Floating Action Button to the given alignment (default bottom‑trailing).
    /// Usage:
    /// ```swift
    /// someView
    ///   .fabOverlay { FAB { /* action */ } }
    /// ```
    /// Note: Positioning of the FAB can also be handled by the parent view using `.position()` if desired.
    func fabOverlay<FabContent: View>(
        alignment: Alignment = .bottomTrailing,
        padding: EdgeInsets = EdgeInsets(top: 0, leading: 0, bottom: 24, trailing: 24),
        padForSafeArea: Bool = true,
        @ViewBuilder _ fab: @escaping () -> FabContent
    ) -> some View {
        modifier(FABOverlayModifier(alignment: alignment, padding: padding, padForSafeArea: padForSafeArea, fab: fab))
    }
}

// MARK: - Preview

struct FAB_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ZStack {
                #if os(macOS)
                Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
                #else
                Color(UIColor.systemBackground).ignoresSafeArea()
                #endif
                Text("Content")
            }
            .fabOverlay {
                FAB(size: .regular, style: .primary, tint: .accentColor) {
                    print("FAB tapped")
                }
            }
            .previewDisplayName("Default")

            ZStack {
                #if os(macOS)
                Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
                #else
                Color(UIColor.systemBackground).ignoresSafeArea()
                #endif
                Text("Loading FAB")
            }
            .fabOverlay {
                FAB(isLoading: true, style: .destructive, tint: .red) {
                    // no-op while loading
                }
            }
            .previewDisplayName("Loading")
        }
    }
}
