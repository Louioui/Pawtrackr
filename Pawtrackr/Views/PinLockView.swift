//
//  PinLockView.swift
//  Pawtrackr
//
//  Standalone 4-digit PIN (default: 1994) + a reusable gate wrapper.
//  No changes required in PawtrackrApp.swift.
//

import SwiftUI

// MARK: - Gate Wrapper
/// Wrap any sensitive content with this. While locked, it shows the PIN UI.
/// Usage:
///   PinLockGate { ClientsView() }   // or PetHistoryView(), etc.
public struct PinLockGate<Content: View>: View {
    @State private var isUnlocked = false
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var appSettings: AppSettings
    @State private var inactivityTimer: Timer? = nil
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        gateContent
            .simultaneousGesture(activityResetGesture)
            .onChange(of: scenePhase) { _, phase in
                if appSettings.autoLockOnBackground, phase != .active {
                    isUnlocked = false
                    invalidateInactivityTimer()
                } else if phase == .active {
                    resetInactivityLock()
                }
            }
            .onChange(of: appSettings.autoLockAfterInactivity) { _, _ in resetInactivityLock() }
            .onChange(of: appSettings.isBiometricLockEnabled) { _, _ in resetInactivityLock() }
            .onChange(of: isUnlocked) { _, unlocked in
                unlocked ? resetInactivityLock() : invalidateInactivityTimer()
            }
            .onAppear { resetInactivityLock() }
            .onDisappear { invalidateInactivityTimer() }
    }

    @ViewBuilder
    private var gateContent: some View {
        if isUnlocked || !appSettings.isLockEnabled {
            content
        } else {
            PinLockView(isUnlocked: $isUnlocked)
        }
    }

    private var activityResetGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in resetInactivityLock() }
            .onEnded { _ in resetInactivityLock() }
    }

    private func resetInactivityLock() {
        invalidateInactivityTimer()
        guard appSettings.autoLockAfterInactivity, appSettings.isLockEnabled else { return }
        let interval = max(1, appSettings.idleLockMinutes * 60)
        inactivityTimer = Timer.scheduledTimer(withTimeInterval: Double(interval), repeats: false) { _ in
            isUnlocked = false
        }
    }

    private func invalidateInactivityTimer() {
        inactivityTimer?.invalidate()
        inactivityTimer = nil
    }
}

// MARK: - Lock Screen (4 digits; default PIN 1994)
public struct PinLockView: View {
    @EnvironmentObject private var appSettings: AppSettings
    @State private var authenticator = BiometricAuthenticator()
    @Binding var isUnlocked: Bool
    @State private var digits: [Int] = []
    @State private var shakeOffset: CGFloat = 0

    // Uses AppSettings.appPIN for a changeable PIN.

    public init(isUnlocked: Binding<Bool>) {
        self._isUnlocked = isUnlocked
    }

    public var body: some View {
        lockContent
            .padding(24)
            .frame(maxWidth: 420)
            .onChange(of: digits) { _, _ in validateIfComplete() }
            .onAppear(perform: authenticateWithBiometrics)
            .accessibilityElement(children: .contain)
    }

    private var lockContent: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 20)
            titleSection
            pinDots
            keypad
            Spacer()
        }
    }

    private var titleSection: some View {
        VStack(spacing: 8) {
            Text(NSLocalizedString("pin.enter", comment: "")).font(.title2).bold()
            Text(NSLocalizedString("pin.requirement", comment: ""))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var pinDots: some View {
        HStack(spacing: 16) {
            ForEach(0..<4, id: \.self) { idx in
                Circle()
                    .fill(idx < digits.count ? Color.primary : Color.secondary.opacity(0.25))
                    .frame(width: 14, height: 14)
            }
        }
        .offset(x: shakeOffset)
        .animation(.easeInOut(duration: 0.06), value: shakeOffset)
    }

    private var keypad: some View {
        VStack(spacing: 12) {
            keyRow([1,2,3])
            keyRow([4,5,6])
            keyRow([7,8,9])
            keypadBottomRow
        }
    }

    private var keypadBottomRow: some View {
        HStack(spacing: 12) {
            if authenticator.biometricType() != .none {
                KeyButton(systemName: authenticator.biometricType() == .faceID ? "faceid" : "touchid") {
                    authenticateWithBiometrics()
                }
                .accessibilityLabel("Authenticate with Biometrics")
            } else {
                KeypadSpacer()
            }
            KeyButton(label: "0") { tapDigit(0) }
            KeyButton(systemName: "delete.left.fill") { deleteDigit() }
                .accessibilityLabel("Delete")
        }
    }

    private func authenticateWithBiometrics() {
        if authenticator.biometricType() != .none {
            authenticator.authenticate { success, error in
                if success {
                    isUnlocked = true
                }
            }
        }
    }

    // MARK: - Rows
    @ViewBuilder
    private func keyRow(_ values: [Int]) -> some View {
        HStack(spacing: 12) {
            ForEach(values, id: \.self) { v in
                KeyButton(label: String(v)) { tapDigit(v) }
            }
        }
    }

    // MARK: - Actions
    private func tapDigit(_ v: Int) {
        guard digits.count < 4 else { return }
        digits.append(v)
    }

    private func deleteDigit() {
        guard !digits.isEmpty else { return }
        _ = digits.removeLast()
    }

    private func validateIfComplete() {
        guard digits.count == 4 else { return }
        let entered = digits.map(String.init).joined()
        if appSettings.validatePIN(entered) {
            isUnlocked = true
        } else {
            performShake()
            HapticManager.notify(.error)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                digits.removeAll()
            }
        }
    }

    private func performShake() {
        let sequence: [CGFloat] = [-10, 10, -8, 8, -5, 5, 0]
        var delay: Double = 0
        for x in sequence {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeInOut(duration: 0.06)) { shakeOffset = x }
            }
            delay += 0.06
        }
    }
}

// MARK: - Keypad Pieces
private struct KeyButton: View {
    var label: String? = nil
    var systemName: String? = nil
    var action: () -> Void

    init(label: String, action: @escaping () -> Void) {
        self.label = label; self.action = action
    }
    init(systemName: String, action: @escaping () -> Void) {
        self.systemName = systemName; self.action = action
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Color.secondary.opacity(0.12))
                if let label { Text(label).font(.title2).fontWeight(.semibold) }
                if let systemName { Image(systemName: systemName).font(.title2) }
            }
            .frame(width: 74, height: 74)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
    }
}

private struct KeypadSpacer: View {
    var body: some View { Circle().fill(Color.clear).frame(width: 74, height: 74) }
}
