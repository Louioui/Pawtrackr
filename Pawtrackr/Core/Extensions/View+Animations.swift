import SwiftUI

/// A reusable view modifier that adds a subtle 'breathing' effect to status indicators.
struct BreathingModifier: ViewModifier {
    @State private var opacity: Double = 0.5

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                    opacity = 1.0
                }
            }
    }
}

/// A view that animates currency changes using the modern content transition API.
struct OdometerLabel: View {
    let value: Decimal
    
    var body: some View {
        Text(value, format: .currency(code: "USD"))
            .contentTransition(.numericText())
            .animation(.snappy, value: value)
    }
}

extension View {
    func breathingEffect() -> some View {
        modifier(BreathingModifier())
    }
}
