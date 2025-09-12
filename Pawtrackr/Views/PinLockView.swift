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
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        Group {
            if isUnlocked {
                content
            } else {
                PinLockView(isUnlocked: $isUnlocked)
            }
        }
        .onChange(of: scenePhase) {
            if scenePhase != .active { isUnlocked = false }
        }
    }
}

// MARK: - Lock Screen (4 digits; default PIN 1994)
public struct PinLockView: View {
    @Binding var isUnlocked: Bool
    @State private var digits: [Int] = []
    @State private var shakeOffset: CGFloat = 0

    // You can swap this to @AppStorage("appPIN") for a changeable PIN.
    private let correctPIN = "1994"

    public init(isUnlocked: Binding<Bool>) {
        self._isUnlocked = isUnlocked
    }

    public var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 20)

            VStack(spacing: 8) {
                Text(NSLocalizedString("pin.enter", comment: "")).font(.title2).bold()
                Text(NSLocalizedString("pin.requirement", comment: ""))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                ForEach(0..<4, id: \.self) { idx in
                    Circle()
                        .fill(idx < digits.count ? Color.primary : Color.secondary.opacity(0.25))
                        .frame(width: 14, height: 14)
                }
            }
            .offset(x: shakeOffset)
            .animation(.easeInOut(duration: 0.06), value: shakeOffset)

            VStack(spacing: 12) {
                keyRow([1,2,3])
                keyRow([4,5,6])
                keyRow([7,8,9])
                HStack(spacing: 12) {
                    KeypadSpacer()
                    KeyButton(label: "0") { tapDigit(0) }
                    KeyButton(systemName: "delete.left.fill") { deleteDigit() }
                        .accessibilityLabel("Delete")
                }
            }

            // (Optional) remove this hint when you’re ready
            Text(NSLocalizedString("pin.hint", comment: ""))
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: 420)
        .onChange(of: digits) { validateIfComplete() }
        .accessibilityElement(children: .contain)
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
        if entered == correctPIN {
            isUnlocked = true
        } else {
            performShake()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
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
