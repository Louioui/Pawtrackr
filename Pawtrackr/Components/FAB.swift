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

    public init(
        diameter: CGFloat = 56,
        systemImage: String = "plus",
        accessibilityLabel: String = "Add New",
        enableHaptics: Bool = true,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.diameter = diameter
        self.systemImage = systemImage
        self.accessibilityLabel = accessibilityLabel
        self.enableHaptics = enableHaptics
        self.isLoading = isLoading
        self.action = action
    }

    public var body: some View {
        Button(action: tap) {
            ZStack {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .frame(width: 56, height: 56)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 24, weight: .bold))
                        .frame(width: 56, height: 56)
                }
            }
            .frame(width: 56, height: 56)
            .background(Circle().fill(Color.accentColor))
            .foregroundColor(.white)
            .shadow(color: .black.opacity(0.2), radius: 5, x: 0, y: 4)
            .contentShape(Circle())
            .accessibilityLabel(Text(accessibilityLabel))
            .accessibilityAddTraits(.isButton)
        }
        .buttonStyle(PressedScaleStyle())
        .onHover { hovering in
            withAnimation {
                isHovering = hovering
            }
        }
        .scaleEffect(isHovering ? 1.1 : 1.0)
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
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

// MARK: - Overlay helper

public struct FABOverlayModifier<FabContent: View>: ViewModifier {
    let alignment: Alignment
    let padding: EdgeInsets
    let fab: () -> FabContent

    public init(
        alignment: Alignment = .bottomTrailing,
        padding: EdgeInsets = EdgeInsets(top: 0, leading: 0, bottom: 24, trailing: 24),
        @ViewBuilder fab: @escaping () -> FabContent
    ) {
        self.alignment = alignment
        self.padding = padding
        self.fab = fab
    }

    public func body(content: Content) -> some View {
        content.overlay(alignment: alignment) {
            fab()
                .padding(padding)
                .ignoresSafeArea(edges: [.bottom])
        }
    }
}

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
        @ViewBuilder _ fab: @escaping () -> FabContent
    ) -> some View {
        modifier(FABOverlayModifier(alignment: alignment, padding: padding, fab: fab))
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
                FAB {
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
                FAB(isLoading: true) {
                    // no-op while loading
                }
            }
            .previewDisplayName("Loading + Custom Gradient")
        }
    }
}
