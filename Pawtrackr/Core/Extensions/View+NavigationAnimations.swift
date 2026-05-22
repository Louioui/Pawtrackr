import SwiftUI

/// A view modifier that provides a 'magnetic' focus effect, gently scaling up 
/// focused elements to guide the user's attention.
struct MagneticFocusModifier: ViewModifier {
    let isFocused: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(isFocused ? 1.02 : 1.0)
            .shadow(color: isFocused ? .primary.opacity(0.15) : .clear, radius: 10, x: 0, y: 5)
            .animation(.snappy, value: isFocused)
    }
}

extension View {
    func magneticFocus(isFocused: Bool) -> some View {
        modifier(MagneticFocusModifier(isFocused: isFocused))
    }
    
    /// Provides a seamless hero transition for images between different view states.
    func heroTransition(id: String, in namespace: Namespace.ID) -> some View {
        self.matchedGeometryEffect(id: id, in: namespace)
    }
}
