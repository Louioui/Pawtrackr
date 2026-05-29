import SwiftUI

#if os(macOS)
import AppKit

/// A view that adds a glassmorphic blur to its parent's background.
struct GlassmorphicBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = .sidebar
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

extension View {
    func glassmorphicSidebar() -> some View {
        self.background(GlassmorphicBackground())
    }
}
#else
extension View {
    func glassmorphicSidebar() -> some View {
        self
    }
}
#endif
