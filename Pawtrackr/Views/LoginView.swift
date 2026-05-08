
import SwiftUI

struct LoginView: View {
    @Environment(AuthenticationViewModel.self) private var authViewModel
    @Environment(AppSettings.self) private var appSettings
    @State private var unlocked = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.blue.opacity(0.15), Color.purple.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                VStack(spacing: 6) {
                    Image(systemName: "pawprint.fill").font(.largeTitle)
                    Text(NSLocalizedString("login.app_name", comment: "")).font(.title.bold())
                    Text(NSLocalizedString("login.enter_pin", comment: "")).font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.bottom, 8)

                PinLockView(isUnlocked: $unlocked)
                    .onChange(of: unlocked) { _, newValue in
                        if newValue { authViewModel.signInAfterUnlock() }
                    }
            }
            .padding(24)
        }
    }
}
