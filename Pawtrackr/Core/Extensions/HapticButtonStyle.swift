import SwiftUI

/// A button style that combines scale-down animation with haptic feedback.
struct HapticPressButtonStyle: ButtonStyle {
    let style: HapticManager.Impact

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.snappy, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    HapticManager.impact(style)
                }
            }
    }
}

extension View {
    func hapticButtonStyle(_ style: HapticManager.Impact = .light) -> some View {
        self.buttonStyle(HapticPressButtonStyle(style: style))
    }
}
