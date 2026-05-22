import SwiftUI

struct PrivacyScreen: View {
    var body: some View {
        ZStack {
            #if os(iOS)
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            #else
            Color.black.opacity(0.8).ignoresSafeArea()
            #endif
            
            VStack(spacing: 20) {
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 80))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.purple)
                
                Text("Pawtrackr")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.primary)
                
                Text("Content hidden for security")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
