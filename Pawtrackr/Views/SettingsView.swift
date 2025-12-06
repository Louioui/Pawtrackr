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
    @State private var showPruneResult = false
    @State private var pruneResultMessage = ""

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
                    businessSettingsCard
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
            .navigationTitle("settings.title")
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
            .alert("common.success", isPresented: $showPruneResult) {
                Button("common.ok", role: .cancel) { }
            } message: {
                Text(pruneResultMessage)
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
            try dataPruner.pruneVisitPhotos(olderThan: date, keepRecentPhotosPerPet: 2)
            pruneResultMessage = String(
                format: NSLocalizedString("settings.data_management.prune_success_fmt", comment: ""),
                Formatters.dateOnly.string(from: date)
            )
            showPruneResult = true
            HapticManager.notify(.success)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    // MARK: - UI Sections
    private var headerBar: some View {
        HStack {
            Text("settings.security.title").font(.headline)
            Spacer()
            Button { } label: { Image(systemName: "questionmark.circle").foregroundStyle(.secondary) }
                .accessibilityLabel(Text("settings.security.question_a11y"))
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
                    Text(appSettings.isBiometricLockEnabled ? "settings.security.status.active_title" : "settings.security.status.inactive_title")
                        .font(.headline).foregroundStyle(.white)
                    Text(appSettings.isBiometricLockEnabled ? "settings.security.status.active_subtitle" : "settings.security.status.inactive_subtitle")
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
                    Text("settings.pin.title").font(.headline)
                    Text("settings.pin.subtitle").font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                HStack {
                    HStack(spacing: 10) {
                        Circle().fill(DS.ColorToken.primary.opacity(0.12)).frame(width: 40, height: 40)
                            .overlay(Image(systemName: "key.fill").foregroundStyle(DS.ColorToken.primary))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("settings.pin.status").font(.subheadline.weight(.semibold))
                            Text(pinStatusSubtitle).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(appSettings.isBiometricLockEnabled ? "settings.pin.status.enabled" : "settings.pin.status.disabled")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(appSettings.isBiometricLockEnabled ? DS.ColorToken.success : Color.gray.opacity(0.5), in: Capsule())
                        .foregroundStyle(.white)
                }
                Button {
                    showChangePIN = true
                } label: {
                    Label("settings.pin.change", systemImage: "pencil").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(DS.ColorToken.primary)
                Button {
                    appSettings.isBiometricLockEnabled.toggle()
                } label: {
                    Label(appSettings.isBiometricLockEnabled ? "settings.pin.disable" : "settings.pin.enable", systemImage: appSettings.isBiometricLockEnabled ? "xmark.circle" : "checkmark.circle")
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

    private var autoLockCard: some View {
        Card(elevation: .regular) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("settings.autolock.title").font(.headline)
                    Text("settings.autolock.subtitle").font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                toggleRow(title: "settings.autolock.on_background.title", subtitle: "settings.autolock.on_background.subtitle", isOn: $appSettings.autoLockOnBackground)
                toggleRow(title: "settings.autolock.on_idle.title", subtitle: "settings.autolock.on_idle.subtitle", isOn: $appSettings.autoLockAfterInactivity)
                toggleRow(title: "settings.autolock.on_sensitive.title", subtitle: "settings.autolock.on_sensitive.subtitle", isOn: .constant(true))
                    .disabled(true)
            }
        }
        .padding(.horizontal)
    }

    private func toggleRow(title: LocalizedStringKey, subtitle: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
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
                    Text("settings.tips.title").font(.subheadline.weight(.semibold))
                    Group {
                        Text("settings.tips.tip1")
                        Text("settings.tips.tip2")
                        Text("settings.tips.tip3")
                        Text("settings.tips.tip4")
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
                Text("settings.data_management.title").font(.headline)
                Picker("settings.data_management.prune_picker_title", selection: $viewModel.pruningThreshold) {
                    ForEach(SettingsViewModel.PruningThreshold.allCases) { threshold in
                        Text(threshold.title).tag(threshold)
                    }
                }
                .pickerStyle(.segmented)
                Button("settings.data_management.prune_button", role: .destructive) { showingConfirmation = true }
                    .disabled(viewModel.pruningThreshold == .never)
            }
        }
        .padding(.horizontal)
    }

    private var businessSettingsCard: some View {
        Card(elevation: .regular) {
            VStack(alignment: .leading, spacing: 12) {
                Text("settings.business.title").font(.headline)
                Divider()
                NavigationLink(destination: ServiceManagementView(modelContext: modelContext)) {
                    HStack {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.headline)
                            .frame(width: 30)
                        VStack(alignment: .leading) {
                            Text("settings.business.services_title")
                                .font(.headline)
                            Text("settings.business.services_subtitle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
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
                    Text("settings.pin.change.title").font(.title3.weight(.semibold))
                    Text("settings.pin.change.subtitle").font(.caption).foregroundStyle(.secondary)
                }
                VStack(spacing: 12) {
                    pinRow(title: "settings.pin.change.current", binding: $current)
                    pinRow(title: "settings.pin.change.new", binding: $newPIN)
                    pinRow(title: "settings.pin.change.confirm", binding: $confirmPIN)
                }
                Spacer(minLength: 0)
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("common.cancel") { isPresented = false } }
                ToolbarItem(placement: .confirmationAction) { Button("settings.pin.change.update") { updatePIN() } }
            }
        }
    }

    @ViewBuilder
    private func pinRow(title: LocalizedStringKey, binding: Binding<[String]>) -> some View {
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
        guard cur.count == 4, np.count == 4, cp.count == 4 else { errorMessage = NSLocalizedString("settings.pin.change.error.incomplete", comment: ""); return }
        guard cur == appSettings.appPIN else { errorMessage = NSLocalizedString("settings.pin.change.error.incorrect", comment: ""); return }
        guard np == cp else { errorMessage = NSLocalizedString("settings.pin.change.error.mismatch", comment: ""); return }
        appSettings.appPIN = np
        appSettings.lastPINChangeDate = Date()
        HapticManager.notify(.success)
        isPresented = false
    }
}
