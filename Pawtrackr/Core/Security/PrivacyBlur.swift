import SwiftUI

struct PrivacyBlurModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @State private var isBlurred = false

    func body(content: Content) -> some View {
        content
            .blur(radius: isBlurred ? 20 : 0)
            .onChange(of: scenePhase) { _, newPhase in
                isBlurred = (newPhase == .inactive || newPhase == .background)
            }
    }
}

extension View {
    func privacyBlur() -> some View {
        modifier(PrivacyBlurModifier())
    }
}
