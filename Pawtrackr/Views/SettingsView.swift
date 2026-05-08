//
//  SettingsView.swift
//  Pawtrackr
//
//  Created by Gemini on 9/15/25.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var appSettings
    @State private var showChangePIN = false
    @State private var pinChangeError: String? = nil
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var cloudKitMonitor = CloudKitMonitor.shared
    @State private var versionTapCount = 0
    @State private var showDiagnostics = false
    private let wrapsInNavigationStack: Bool

    init(wrapsInNavigationStack: Bool = true) {
        self.wrapsInNavigationStack = wrapsInNavigationStack
    }

    var body: some View {
        if wrapsInNavigationStack {
            NavigationStack {
                settingsContent
            }
        } else {
            settingsContent
        }
    }

    private var iCloudStatusRow: some View {
        HStack(spacing: 12) {
            Image(systemName: cloudKitMonitor.statusIconName)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(cloudKitTintColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(cloudKitMonitor.accountState.displayLabel)
                    .font(.subheadline.weight(.medium))
                Text(syncStateLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var cloudKitTintColor: Color {
        switch cloudKitMonitor.statusTint {
        case .success: return .green
        case .neutral: return .secondary
        case .warning: return .orange
        case .danger: return .red
        }
    }

    private var syncStateLabel: String {
        switch cloudKitMonitor.syncState {
        case .syncing: return NSLocalizedString("cloudkit.status.syncing", value: "Syncing…", comment: "")
        case .error: return NSLocalizedString("cloudkit.status.error", value: "Sync error", comment: "")
        case .idle: return NSLocalizedString("cloudkit.status.idle", value: "Idle", comment: "")
        }
    }

    private var appVersionString: String {
        let dict = Bundle.main.infoDictionary ?? [:]
        let version = (dict["CFBundleShortVersionString"] as? String) ?? "—"
        let build = (dict["CFBundleVersion"] as? String) ?? "—"
        return "\(version) (\(build))"
    }

    private var settingsContent: some View {
        @Bindable var appSettings = appSettings

        return Form {
            Section(header: Text("Business Profile")) {
                TextField("Business Name", text: $appSettings.businessName)
                TextField("Currency Symbol", text: $appSettings.currencySymbol)
                    .frame(width: 50)
            }

            Section(header: Text("Security")) {
                securityStatusCard
                    .listRowInsets(EdgeInsets())

                Toggle("Enable App Lock", isOn: $appSettings.isLockEnabled)

                if appSettings.isLockEnabled {
                    Toggle("Biometric Unlock", isOn: $appSettings.isBiometricLockEnabled)

                    Button("Change PIN") {
                        showChangePIN = true
                    }
                }
            }

            Section(header: Text("Data Export")) {
                if let clientsExport = try? ExportService.shared.exportClientsToCSV(modelContext: modelContext) {
                    ShareLink(item: clientsExport, preview: SharePreview("Clients Export", image: Image(systemName: "person.3.fill"))) {
                        Label("Export Clients (CSV)", systemImage: "square.and.arrow.up")
                    }
                }

                if let visitsExport = try? ExportService.shared.exportVisitsToCSV(modelContext: modelContext) {
                    ShareLink(item: visitsExport, preview: SharePreview("Visits Export", image: Image(systemName: "calendar"))) {
                        Label("Export Visits (CSV)", systemImage: "square.and.arrow.up")
                    }
                }
            }

            Section {
                iCloudStatusRow
                if cloudKitMonitor.accountState.isAvailable {
                    Button {
                        Task { await cloudKitMonitor.forceSync() }
                    } label: {
                        Label(NSLocalizedString("cloudkit.action.sync_now", value: "Sync Now", comment: ""),
                              systemImage: "arrow.clockwise.icloud")
                    }
                    .disabled({
                        if case .syncing = cloudKitMonitor.syncState { return true }
                        return false
                    }())
                }
                if showDiagnostics {
                    NavigationLink {
                        CloudKitDiagnosticsView()
                    } label: {
                        Label(NSLocalizedString("cloudkit.diagnostics.title", value: "iCloud Diagnostics", comment: ""),
                              systemImage: "stethoscope")
                    }
                }
            } header: {
                Text(NSLocalizedString("settings.section.icloud", value: "iCloud", comment: ""))
            } footer: {
                if let err = cloudKitMonitor.lastErrorMessage, case .error = cloudKitMonitor.syncState {
                    Text(err).foregroundStyle(.red)
                } else {
                    Text(cloudKitMonitor.lastSyncSummary).font(.caption)
                }
            }

            Section {
                HStack {
                    Text(NSLocalizedString("settings.version", value: "Version", comment: ""))
                    Spacer()
                    Text(appVersionString).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    versionTapCount += 1
                    if versionTapCount >= 7 {
                        showDiagnostics = true
                        versionTapCount = 0
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("settings.title", comment: ""))
#if os(iOS)
        .navigationBarTitleDisplayMode(.large)
#endif
        .sheet(isPresented: $showChangePIN) {
            ChangePINSheet(isPresented: $showChangePIN, errorMessage: $pinChangeError)
                .environment(appSettings)
        }
        .alert(NSLocalizedString("common.error", comment: ""), isPresented: Binding(get: { pinChangeError != nil }, set: { if !$0 { pinChangeError = nil } })) {
            Button(NSLocalizedString("common.ok", comment: ""), role: .cancel) { }
        } message: { Text(pinChangeError ?? "") }
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
            LinearGradient(colors: [appSettings.isLockEnabled ? DS.ColorToken.success : Color.gray, appSettings.isLockEnabled ? Color.green.opacity(0.8) : Color.gray.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            HStack(spacing: 12) {
                Circle().fill(Color.white.opacity(0.2)).frame(width: 48, height: 48)
                    .overlay(Image(systemName: appSettings.isLockEnabled ? "checkmark.shield.fill" : "lock.open.fill").font(.title2).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString(appSettings.isLockEnabled ? "settings.security.status.active_title" : "settings.security.status.inactive_title", comment: ""))
                        .font(.headline).foregroundStyle(.white)
                    Text(NSLocalizedString(appSettings.isLockEnabled ? "settings.security.status.active_subtitle" : "settings.security.status.inactive_subtitle", comment: ""))
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
    @Environment(AppSettings.self) private var appSettings
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
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
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
