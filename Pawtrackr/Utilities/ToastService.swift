//
//  ToastService.swift
//  Pawtrackr
//
//  Global service to manage "Toasts" (temporary alerts) for live activity.
//

import SwiftUI
import Observation

@MainActor
@Observable
final class ToastService {
    static let shared = ToastService()

    struct Toast: Identifiable {
        let id = UUID()
        let message: String
        let icon: String
        let tint: Color
    }

    private(set) var currentToast: Toast?
    private var timer: Timer?

    private init() {}

    func show(message: String, icon: String = "info.circle", tint: Color = .blue) {
        // Clear existing
        timer?.invalidate()
        currentToast = nil

        // Show new
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            currentToast = Toast(message: message, icon: icon, tint: tint)
        }

        // Auto-hide
        timer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                withAnimation(.easeIn(duration: 0.25)) {
                    self?.currentToast = nil
                }
            }
        }
    }
}

struct ToastOverlay: ViewModifier {
    @State private var toastService = ToastService.shared
    
    func body(content: Content) -> some View {
        ZStack {
            content
            
            if let toast = toastService.currentToast {
                VStack {
                    HStack(spacing: 12) {
                        Image(systemName: toast.icon)
                            .foregroundStyle(toast.tint)
                            .font(.headline)
                        
                        Text(toast.message)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background {
                        #if os(iOS)
                        Capsule()
                            .fill(.background)
                            .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                        #else
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(nsColor: .windowBackgroundColor))
                            .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                        #endif
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    
                    Spacer()
                }
                .zIndex(999)
            }
        }
    }
}

extension View {
    func toastOverlay() -> some View {
        modifier(ToastOverlay())
    }
}
