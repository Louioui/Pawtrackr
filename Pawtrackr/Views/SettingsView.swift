//
//  SettingsView.swift
//  Pawtrackr
//
//  Created by Gemini on 9/15/25.
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appSettings: AppSettings
    @StateObject private var viewModel = SettingsViewModel()
    @State private var showingConfirmation = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showChangePIN = false
    @State private var pinChangeError: String? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headerBar
                    securityStatusCard
                    pinManagementCard
                    autoLockCard
                    securityTipsCard
                    dataManagementCard
                }
                .padding(.vertical, 8)
            }
            .sheet(isPresented: $showChangePIN) {
                ChangePINSheet(isPresented: $showChangePIN, errorMessage: $pinChangeError)
                    .environmentObject(appSettings)
            }
            .alert("common.error", isPresented: Binding(get: { pinChangeError != nil }, set: { if !$0 { pinChangeError = nil } })) {
                Button("common.ok", role: .cancel) { }
            } message: { Text(pinChangeError ?? "") }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .alert("settings.data_management.confirm.title", isPresented: $showingConfirmation) {
                Button("common.cancel", role: .cancel) { }
                Button("settings.data_management.confirm.delete", role: .destructive) {
                    pruneData()
                }
            } message: {
                Text("settings.data_management.confirm.message")
            }
            .alert("common.error", isPresented: $showError) {
                Button("common.ok", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func pruneData() {
        guard let date = viewModel.pruningThreshold.date else {
            return
        }
        
        let dataPruner = DataPruner(modelContext: modelContext)
        do {
            try dataPruner.pruneVisits(olderThan: date)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    // MARK: - UI Sections
    private var headerBar: some View {
        HStack {
            Text("Security Settings").font(.headline)
            Spacer()
            Button { } label: { Image(systemName: "questionmark.circle").foregroundStyle(.secondary) }
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
                    Text(appSettings.isBiometricLockEnabled ? "Security Active" : "Security Disabled")
                        .font(.headline).foregroundStyle(.white)
                    Text(appSettings.isBiometricLockEnabled ? "PIN lock is enabled and protecting your data" : "PIN lock is currently disabled")
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
                    Text("PIN Lock Settings").font(.headline)
                    Text("Manage your 4-digit security PIN").font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                HStack {
                    HStack(spacing: 10) {
                        Circle().fill(DS.ColorToken.primary.opacity(0.12)).frame(width: 40, height: 40)
                            .overlay(Image(systemName: "key.fill").foregroundStyle(DS.ColorToken.primary))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("PIN Status").font(.subheadline.weight(.semibold))
                            Text(pinStatusSubtitle).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(appSettings.isBiometricLockEnabled ? "Enabled" : "Disabled")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(appSettings.isBiometricLockEnabled ? DS.ColorToken.success : Color.gray.opacity(0.5), in: Capsule())
                        .foregroundStyle(.white)
                }
                Button {
                    showChangePIN = true
                } label: {
                    Label("Change PIN", systemImage: "pencil").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(DS.ColorToken.primary)
                Button {
                    appSettings.isBiometricLockEnabled.toggle()
                } label: {
                    Label(appSettings.isBiometricLockEnabled ? "Disable PIN Lock" : "Enable PIN Lock", systemImage: appSettings.isBiometricLockEnabled ? "xmark.circle" : "checkmark.circle")
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
            return "Last changed \(rel)"
        } else {
            return "Never changed"
        }
    }

    private var autoLockCard: some View {
        Card(elevation: .regular) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Auto-Lock Behavior").font(.headline)
                    Text("When the PIN lock activates automatically").font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                toggleRow(title: "Lock on app background", subtitle: "Activate PIN when switching apps", isOn: $appSettings.autoLockOnBackground)
                toggleRow(title: "Lock after inactivity", subtitle: "Auto-lock after 5 minutes idle", isOn: $appSettings.autoLockAfterInactivity)
                toggleRow(title: "Require PIN for sensitive data", subtitle: "Extra security for payments & client info", isOn: .constant(true))
            }
        }
        .padding(.horizontal)
    }

    private func toggleRow(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: isOn).labelsHidden()
        }
    }

    private var securityTipsCard: some View {
        Card(elevation: .regular) {
            HStack(alignment: .top, spacing: 12) {
                Circle().fill(DS.ColorToken.info.opacity(0.12)).frame(width: 32, height: 32)
                    .overlay(Image(systemName: "lightbulb.fill").foregroundStyle(DS.ColorToken.info))
                VStack(alignment: .leading, spacing: 6) {
                    Text("Security Tips").font(.subheadline.weight(.semibold))
                    Group {
                        Text("• Use a unique PIN that's not easily guessed")
                        Text("• Change your PIN regularly for better security")
                        Text("• Keep your device updated with latest security patches")
                        Text("• Don't share your PIN with unauthorized users")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal)
    }

    private var dataManagementCard: some View {
        Card(elevation: .regular) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Data Management").font(.headline)
                Picker("Prune Data Older Than", selection: $viewModel.pruningThreshold) {
                    ForEach(SettingsViewModel.PruningThreshold.allCases) { threshold in
                        Text(threshold.rawValue).tag(threshold)
                    }
                }
                .pickerStyle(.segmented)
                Button("Prune Now", role: .destructive) { showingConfirmation = true }
                    .disabled(viewModel.pruningThreshold == .never)
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Change PIN Sheet
private struct ChangePINSheet: View {
    @EnvironmentObject private var appSettings: AppSettings
    @Binding var isPresented: Bool
    @Binding var errorMessage: String?

    @State private var current: [String] = Array(repeating: "", count: 4)
    @State private var newPIN: [String] = Array(repeating: "", count: 4)
    @State private var confirmPIN: [String] = Array(repeating: "", count: 4)

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                VStack(spacing: 6) {
                    Circle().fill(DS.ColorToken.primary.opacity(0.12)).frame(width: 64, height: 64)
                        .overlay(Image(systemName: "key.fill").font(.title).foregroundStyle(DS.ColorToken.primary))
                    Text("Change PIN").font(.title3.weight(.semibold))
                    Text("Enter your current PIN, then set a new one").font(.caption).foregroundStyle(.secondary)
                }
                VStack(spacing: 12) {
                    pinRow(title: "Current PIN", binding: $current)
                    pinRow(title: "New PIN", binding: $newPIN)
                    pinRow(title: "Confirm New PIN", binding: $confirmPIN)
                }
                Spacer(minLength: 0)
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { isPresented = false } }
                ToolbarItem(placement: .confirmationAction) { Button("Update PIN") { updatePIN() } }
            }
        }
    }

    @ViewBuilder
    private func pinRow(title: String, binding: Binding<[String]>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold))
            HStack(spacing: 10) {
                ForEach(0..<4, id: \.self) { idx in
                    TextField("", text: Binding(get: { binding.wrappedValue[idx] }, set: { binding.wrappedValue[idx] = String($0.prefix(1)) }))
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .frame(width: 44)
                }
            }
        }
    }

    private func updatePIN() {
        let cur = current.joined()
        let np = newPIN.joined()
        let cp = confirmPIN.joined()
        guard cur.count == 4, np.count == 4, cp.count == 4 else { errorMessage = "Enter all 4 digits for each"; return }
        guard cur == appSettings.appPIN else { errorMessage = "Current PIN is incorrect"; return }
        guard np == cp else { errorMessage = "New PIN entries do not match"; return }
        appSettings.appPIN = np
        appSettings.lastPINChangeDate = Date()
        HapticManager.notify(.success)
        isPresented = false
    }
}
