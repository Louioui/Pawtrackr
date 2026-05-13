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
    @State private var clientsDoc: ExportDocument? = nil
    @State private var visitsDoc: ExportDocument? = nil
    @State private var isExportingClients = false
    @State private var isExportingVisits = false
    @State private var exportError: String? = nil
    @State private var showDisableLockConfirm = false
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

                Toggle("Enable App Lock", isOn: Binding(
                    get: { appSettings.isLockEnabled },
                    set: { newValue in
                        if !newValue && appSettings.isLockEnabled {
                            // Confirm before disabling — wallet/business app, the lock is
                            // a major safety boundary that shouldn't be removed by a stray tap.
                            showDisableLockConfirm = true
                        } else {
                            appSettings.isLockEnabled = newValue
                        }
                    }
                ))
                .accessibilityIdentifier("settings.appLockToggle")

                if appSettings.isLockEnabled {
                    Toggle("Biometric Unlock", isOn: $appSettings.isBiometricLockEnabled)
                        .accessibilityIdentifier("settings.biometricToggle")

                    Button("Change PIN") {
                        showChangePIN = true
                    }
                    .accessibilityIdentifier("settings.changePIN")
                }
            }

            Section(header: Text("Help")) {
                Button {
                    appSettings.hasSeenAppTour = false
                } label: {
                    Label("Replay App Tour", systemImage: "sparkles.rectangle.stack")
                }
                .accessibilityIdentifier("settings.replayTour")
            }

            Section(header: Text("Data Export")) {
                Button {
                    runExport(kind: .clients)
                } label: {
                    HStack {
                        Label("Export Clients (CSV)", systemImage: "square.and.arrow.up")
                        Spacer()
                        if isExportingClients { ProgressView() }
                    }
                }
                .accessibilityIdentifier("settings.exportClients")
                .disabled(isExportingClients)

                Button {
                    runExport(kind: .visits)
                } label: {
                    HStack {
                        Label("Export Visits (CSV)", systemImage: "square.and.arrow.up")
                        Spacer()
                        if isExportingVisits { ProgressView() }
                    }
                }
                .accessibilityIdentifier("settings.exportVisits")
                .disabled(isExportingVisits)
            }

            Section {
                iCloudStatusRow
                if cloudKitMonitor.accountState.isAvailable {
                    Button {
                        Task { await cloudKitMonitor.forceSync() }
                    } label: {
                        Label(NSLocalizedString("cloudkit.action.check_status", value: "Check iCloud", comment: ""),
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
        .sheet(item: $clientsDoc) { doc in
            exportShareSheet(
                doc: doc,
                title: NSLocalizedString("settings.export.clients_ready", value: "Clients Export Ready", comment: ""),
                icon: "person.3.fill",
                previewTitle: NSLocalizedString("settings.export.clients_title", value: "Clients Export", comment: "")
            )
        }
        .sheet(item: $visitsDoc) { doc in
            exportShareSheet(
                doc: doc,
                title: NSLocalizedString("settings.export.visits_ready", value: "Visits Export Ready", comment: ""),
                icon: "calendar",
                previewTitle: NSLocalizedString("settings.export.visits_title", value: "Visits Export", comment: "")
            )
        }
        .alert(NSLocalizedString("common.error", comment: ""), isPresented: Binding(get: { pinChangeError != nil }, set: { if !$0 { pinChangeError = nil } })) {
            Button(NSLocalizedString("common.ok", comment: ""), role: .cancel) { }
        } message: { Text(pinChangeError ?? "") }
        .alert("Export Failed", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK", role: .cancel) { }
        } message: { Text(exportError ?? "") }
        .alert("Disable App Lock?", isPresented: $showDisableLockConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Disable", role: .destructive) {
                appSettings.isLockEnabled = false
            }
        } message: {
            Text("Anyone with access to this device will be able to view client data. You can re-enable the lock at any time.")
        }
    }

    private enum ExportKind { case clients, visits }

    private func runExport(kind: ExportKind) {
        let container = modelContext.container
        switch kind {
        case .clients:
            guard !isExportingClients else { return }
            isExportingClients = true
            Task {
                defer { isExportingClients = false }
                do {
                    clientsDoc = try await ExportService.shared.exportClientsToCSVAsync(container: container)
                } catch {
                    exportError = error.localizedDescription
                }
            }
        case .visits:
            guard !isExportingVisits else { return }
            isExportingVisits = true
            Task {
                defer { isExportingVisits = false }
                do {
                    visitsDoc = try await ExportService.shared.exportVisitsToCSVAsync(container: container)
                } catch {
                    exportError = error.localizedDescription
                }
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

    @ViewBuilder
    private func exportShareSheet(doc: ExportDocument, title: String, icon: String, previewTitle: String) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundStyle(DS.ColorToken.primary)
            Text(title).font(.headline)
            ShareLink(
                item: doc,
                preview: SharePreview(previewTitle, image: Image(systemName: icon))
            ) {
                Label(NSLocalizedString("settings.export.share_action", value: "Share via…", comment: ""),
                      systemImage: "square.and.arrow.up")
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(DS.ColorToken.primary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(.white)
                    .font(.headline)
            }
            Spacer()
        }
        .padding()
#if os(iOS)
        .presentationDetents([.height(240)])
        .presentationDragIndicator(.visible)
#endif
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
