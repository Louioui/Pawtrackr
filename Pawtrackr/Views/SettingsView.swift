//
//  SettingsView.swift
//  Pawtrackr
//
//  Created by Gemini on 9/15/25.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appSettings: AppSettings
    @State private var showChangePIN = false
    @State private var pinChangeError: String? = nil
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headerBar
                    securityStatusCard
                    pinManagementCard
                    
                    
                    
                }
                .padding(.vertical, 8)
            }
            .sheet(isPresented: $showChangePIN) {
                ChangePINSheet(isPresented: $showChangePIN, errorMessage: $pinChangeError)
                    .environmentObject(appSettings)
            }
            .alert(NSLocalizedString("common.error", comment: ""), isPresented: Binding(get: { pinChangeError != nil }, set: { if !$0 { pinChangeError = nil } })) {
                Button(NSLocalizedString("common.ok", comment: ""), role: .cancel) { }
            } message: { Text(pinChangeError ?? "") }
            .navigationTitle(NSLocalizedString("settings.title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .alert(NSLocalizedString("common.error", comment: ""), isPresented: $showError) {
                Button(NSLocalizedString("common.ok", comment: ""), role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    // MARK: - UI Sections
    private var headerBar: some View {
        HStack {
            Text(NSLocalizedString("settings.security.title", comment: "")).font(.headline)
            Spacer()
            Button { } label: { Image(systemName: "questionmark.circle").foregroundStyle(.secondary) }
                .accessibilityLabel(Text(NSLocalizedString("settings.security.question_a11y", comment: "")))
        }
        .padding(.horizontal)
    }

    private var securityStatusCard: some View {
        ZStack {
            LinearGradient(colors: [DS.ColorToken.success, Color.green.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            HStack(spacing: 12) {
                Circle().fill(Color.white.opacity(0.2)).frame(width: 48, height: 48)
                    .overlay(Image(systemName: "checkmark.shield.fill").font(.title2).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString(appSettings.isBiometricLockEnabled ? "settings.security.status.active_title" : "settings.security.status.inactive_title", comment: ""))
                        .font(.headline).foregroundStyle(.white)
                    Text(NSLocalizedString(appSettings.isBiometricLockEnabled ? "settings.security.status.active_subtitle" : "settings.security.status.inactive_subtitle", comment: ""))
                        .font(.caption).foregroundStyle(.white.opacity(0.9))
                }
                Spacer()
            }
            .padding(16)
        }
        .padding(.horizontal)
        .frame(height: 96)
    }

    private var pinManagementCard: some View {
        Card(elevation: .regular) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString("settings.pin.title", comment: "")).font(.headline)
                    Text(NSLocalizedString("settings.pin.subtitle", comment: "")).font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                HStack {
                    HStack(spacing: 10) {
                        Circle().fill(DS.ColorToken.primary.opacity(0.12)).frame(width: 40, height: 40)
                            .overlay(Image(systemName: "key.fill").foregroundStyle(DS.ColorToken.primary))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(NSLocalizedString("settings.pin.status", comment: "")).font(.subheadline.weight(.semibold))
                            Text(pinStatusSubtitle).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(NSLocalizedString(appSettings.isBiometricLockEnabled ? "settings.pin.status.enabled" : "settings.pin.status.disabled", comment: ""))
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(appSettings.isBiometricLockEnabled ? DS.ColorToken.success : Color.gray.opacity(0.5), in: Capsule())
                        .foregroundStyle(.white)
                }
                Button {
                    showChangePIN = true
                } label: {
                    Label(NSLocalizedString("settings.pin.change", comment: ""), systemImage: "pencil").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(DS.ColorToken.primary)
                Button {
                    appSettings.isBiometricLockEnabled.toggle()
                } label: {
                    Label(NSLocalizedString(appSettings.isBiometricLockEnabled ? "settings.pin.disable" : "settings.pin.enable", comment: ""), systemImage: appSettings.isBiometricLockEnabled ? "xmark.circle" : "checkmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal)
    }

    private var pinStatusSubtitle: String {
        if let d = appSettings.lastPINChangeDate {
            let fmt = RelativeDateTimeFormatter()
            fmt.unitsStyle = .full
            let rel = fmt.localizedString(for: d, relativeTo: Date())
            return String(format: NSLocalizedString("settings.pin.status.changed_relative_fmt", comment: ""), rel)
        } else {
            return NSLocalizedString("settings.pin.status.never_changed", comment: "")
        }
    }



}

// MARK: - Change PIN Sheet
private struct ChangePINSheet: View {
    @EnvironmentObject private var appSettings: AppSettings
    @Binding var isPresented: Bool
    @Binding var errorMessage: String?

    @State private var currentPIN: String = ""
    @State private var newPIN: String = ""
    @State private var confirmPIN: String = ""
    @FocusState private var focusedField: PINField?

    private enum PINField {
        case current, new, confirm
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 6) {
                        Circle().fill(DS.ColorToken.primary.opacity(0.12)).frame(width: 64, height: 64)
                            .overlay(Image(systemName: "key.fill").font(.title).foregroundStyle(DS.ColorToken.primary))
                        Text(NSLocalizedString("settings.pin.change.title", comment: "")).font(.title3.weight(.semibold))
                        Text(NSLocalizedString("settings.pin.change.subtitle", comment: "")).font(.caption).foregroundStyle(.secondary)
                    }

                    VStack(spacing: 20) {
                        pinInputField(
                            title: NSLocalizedString("settings.pin.change.current", comment: ""),
                            pin: $currentPIN,
                            field: .current
                        )

                        pinInputField(
                            title: NSLocalizedString("settings.pin.change.new", comment: ""),
                            pin: $newPIN,
                            field: .new
                        )

                        pinInputField(
                            title: NSLocalizedString("settings.pin.change.confirm", comment: ""),
                            pin: $confirmPIN,
                            field: .confirm
                        )
                    }

                    Spacer(minLength: 20)
                }
                .padding()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("common.cancel", comment: "")) { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("settings.pin.change.update", comment: "")) { updatePIN() }
                        .disabled(currentPIN.count != 4 || newPIN.count != 4 || confirmPIN.count != 4)
                }
            }
            .onAppear {
                focusedField = .current
            }
        }
    }

    @ViewBuilder
    private func pinInputField(title: String, pin: Binding<String>, field: PINField) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold))

            HStack(spacing: 12) {
                ForEach(0..<4, id: \.self) { idx in
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(DS.ColorToken.surface)
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(focusedField == field ? DS.ColorToken.primary : DS.ColorToken.border, lineWidth: focusedField == field ? 2 : 1)

                        if idx < pin.wrappedValue.count {
                            Circle()
                                .fill(Color.primary)
                                .frame(width: 12, height: 12)
                        }
                    }
                    .frame(width: 50, height: 56)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                focusedField = field
            }
            .overlay {
                // Hidden text field to capture keyboard input
                TextField("", text: Binding(
                    get: { pin.wrappedValue },
                    set: { newValue in
                        // Only allow numeric characters, max 4 digits
                        let filtered = newValue.filter { $0.isNumber }
                        pin.wrappedValue = String(filtered.prefix(4))

                        // Auto-advance to next field when 4 digits entered
                        if pin.wrappedValue.count == 4 {
                            switch field {
                            case .current: focusedField = .new
                            case .new: focusedField = .confirm
                            case .confirm: focusedField = nil
                            }
                        }
                    }
                ))
                .keyboardType(.numberPad)
                .focused($focusedField, equals: field)
                .opacity(0.01) // Nearly invisible but still functional
                .frame(width: 1, height: 1)
            }
        }
    }

    private func updatePIN() {
        guard currentPIN.count == 4, newPIN.count == 4, confirmPIN.count == 4 else {
            errorMessage = NSLocalizedString("settings.pin.change.error.incomplete", comment: "")
            return
        }
        guard appSettings.validatePIN(currentPIN) else {
            errorMessage = NSLocalizedString("settings.pin.change.error.incorrect", comment: "")
            return
        }
        guard newPIN == confirmPIN else {
            errorMessage = NSLocalizedString("settings.pin.change.error.mismatch", comment: "")
            return
        }
        guard appSettings.changePIN(to: newPIN) else {
            errorMessage = NSLocalizedString("settings.pin.change.error.invalid", comment: "")
            return
        }
        HapticManager.notify(.success)
        isPresented = false
    }
}
