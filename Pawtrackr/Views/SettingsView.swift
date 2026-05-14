//
//  SettingsView.swift
//  Pawtrackr
//
//  Created by Gemini on 9/15/25.
//

import SwiftUI
#if os(iOS)
import UserNotifications
import UIKit
#endif

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
    @State private var lockEnabledOverride: Bool?
    @State private var lockToggleProxy = false
    @State private var notificationAuthState: NotificationAuthState = .unknown
    @State private var showResetFirstRunConfirm = false
    private let wrapsInNavigationStack: Bool

    init(wrapsInNavigationStack: Bool = true) {
        self.wrapsInNavigationStack = wrapsInNavigationStack
    }

    enum NotificationAuthState {
        case unknown, authorized, denied, notDetermined, provisional, ephemeral

        var label: String {
            switch self {
            case .unknown:       return NSLocalizedString("settings.notifications.unknown",       value: "Checking…",               comment: "")
            case .authorized:    return NSLocalizedString("settings.notifications.authorized",    value: "Allowed",                 comment: "")
            case .denied:        return NSLocalizedString("settings.notifications.denied",        value: "Blocked in iOS Settings", comment: "")
            case .notDetermined: return NSLocalizedString("settings.notifications.notDetermined", value: "Not Yet Requested",       comment: "")
            case .provisional:   return NSLocalizedString("settings.notifications.provisional",   value: "Quiet Delivery",          comment: "")
            case .ephemeral:     return NSLocalizedString("settings.notifications.ephemeral",     value: "App Clip Only",           comment: "")
            }
        }

        var icon: String {
            switch self {
            case .authorized, .provisional, .ephemeral: return "bell.badge.fill"
            case .denied:                               return "bell.slash.fill"
            case .notDetermined:                        return "bell.fill"
            case .unknown:                              return "bell"
            }
        }

        var tint: Color {
            switch self {
            case .authorized, .provisional, .ephemeral: return DS.ColorToken.success
            case .denied:                               return DS.ColorToken.danger
            case .notDetermined:                        return DS.ColorToken.warning
            case .unknown:                              return .secondary
            }
        }
    }

    var body: some View {
        if wrapsInNavigationStack {
            NavigationStack { settingsContent }
        } else {
            settingsContent
        }
    }

    // MARK: - Body

    private var settingsContent: some View {
        @Bindable var appSettings = appSettings

        return Form {
            // MARK: Header card
            Section {
                headerCard
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 12, trailing: 0))
            }

            // MARK: Business Profile
            Section {
                TextField(NSLocalizedString("settings.businessName", value: "Business Name", comment: ""),
                          text: $appSettings.businessName)
                TextField(NSLocalizedString("settings.currencySymbol", value: "Currency Symbol", comment: ""),
                          text: $appSettings.currencySymbol)
                    .frame(width: 50)
            } header: {
                sectionHeader(NSLocalizedString("settings.section.businessProfile", value: "Business Profile", comment: ""),
                              icon: "building.2.fill")
            }

            // MARK: Preferences (theme, haptics, notifications)
            Section {
                Picker(selection: $appSettings.preferredColorScheme) {
                    ForEach(AppColorScheme.allCases) { scheme in
                        Text(scheme.displayName).tag(scheme)
                    }
                } label: {
                    Label(NSLocalizedString("settings.appearance", value: "Appearance", comment: ""),
                          systemImage: "circle.lefthalf.filled")
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("settings.themePicker")

                Toggle(isOn: $appSettings.hapticsEnabled) {
                    Label(NSLocalizedString("settings.haptics", value: "Haptic Feedback", comment: ""),
                          systemImage: "hand.tap.fill")
                }
                .accessibilityIdentifier("settings.hapticsToggle")

                #if os(iOS)
                notificationStatusRow
                #endif
            } header: {
                sectionHeader(NSLocalizedString("settings.section.preferences", value: "Preferences", comment: ""),
                              icon: "slider.horizontal.3")
            } footer: {
                Text(NSLocalizedString("settings.preferences.footer",
                                       value: "Appearance applies to the entire app. Haptics affect button taps, toggles, and confirmations.",
                                       comment: ""))
                    .font(.caption)
            }

            // MARK: Security
            Section {
                securityStatusCard
                    .listRowInsets(EdgeInsets())

                Toggle("Enable App Lock", isOn: $lockToggleProxy)
                    .accessibilityIdentifier("settings.appLockToggle")
                    .allowsHitTesting(false)
                    .overlay {
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .onTapGesture(perform: handleLockToggleTap)
                            .accessibilityHidden(true)
                    }
                    .onChange(of: lockToggleProxy) { oldValue, newValue in
                        handleLockToggleChange(from: oldValue, to: newValue)
                    }

                if effectiveLockEnabled {
                    Toggle("Biometric Unlock", isOn: $appSettings.isBiometricLockEnabled)
                        .accessibilityIdentifier("settings.biometricToggle")

                    Button("Change PIN") {
                        showChangePIN = true
                    }
                    .accessibilityIdentifier("settings.changePIN")
                }
            } header: {
                sectionHeader(NSLocalizedString("settings.section.security", value: "Security", comment: ""),
                              icon: "lock.shield.fill")
            }

            // MARK: Data Export
            Section {
                Button {
                    runExport(kind: .clients)
                } label: {
                    HStack {
                        Label("Export Clients (CSV)", systemImage: "person.3.fill")
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
                        Label("Export Visits (CSV)", systemImage: "calendar")
                        Spacer()
                        if isExportingVisits { ProgressView() }
                    }
                }
                .accessibilityIdentifier("settings.exportVisits")
                .disabled(isExportingVisits)
            } header: {
                sectionHeader(NSLocalizedString("settings.section.dataExport", value: "Data Export", comment: ""),
                              icon: "square.and.arrow.up")
            }

            // MARK: iCloud
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
                sectionHeader(NSLocalizedString("settings.section.icloud", value: "iCloud", comment: ""),
                              icon: "icloud.fill")
            } footer: {
                if let err = cloudKitMonitor.lastErrorMessage, case .error = cloudKitMonitor.syncState {
                    Text(err).foregroundStyle(.red)
                } else {
                    Text(cloudKitMonitor.lastSyncSummary).font(.caption)
                }
            }

            // MARK: Help & Support
            Section {
                Button {
                    appSettings.hasSeenAppTour = false
                } label: {
                    Label("Replay App Tour", systemImage: "sparkles.rectangle.stack")
                }
                .accessibilityIdentifier("settings.replayTour")

                Button(role: .destructive) {
                    showResetFirstRunConfirm = true
                } label: {
                    Label(NSLocalizedString("settings.firstRun.reset.action", value: "Reset First-Run State", comment: ""),
                          systemImage: "arrow.counterclockwise.circle")
                }
                .accessibilityIdentifier("settings.resetFirstRun")
            } header: {
                sectionHeader(NSLocalizedString("settings.section.help", value: "Help & Support", comment: ""),
                              icon: "questionmark.circle.fill")
            }

            // MARK: About
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
            } header: {
                sectionHeader(NSLocalizedString("settings.section.about", value: "About", comment: ""),
                              icon: "info.circle.fill")
            }
        }
        .navigationTitle(NSLocalizedString("settings.title", comment: ""))
        .onAppear {
            syncLockToggleProxy()
            refreshNotificationStatus()
        }
        .onChange(of: appSettings.isLockEnabled) { _, _ in
            syncLockToggleProxy()
        }
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
        .alert(NSLocalizedString("common.error", comment: ""),
               isPresented: Binding(get: { pinChangeError != nil }, set: { if !$0 { pinChangeError = nil } })) {
            Button(NSLocalizedString("common.ok", comment: ""), role: .cancel) { }
        } message: { Text(pinChangeError ?? "") }
        .alert("Export Failed",
               isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK", role: .cancel) { }
        } message: { Text(exportError ?? "") }
        .alert("Disable App Lock?", isPresented: $showDisableLockConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Disable", role: .destructive) {
                lockEnabledOverride = false
                appSettings.isLockEnabled = false
                lockToggleProxy = false
            }
        } message: {
            Text("Anyone with access to this device will be able to view client data. You can re-enable the lock at any time.")
        }
        .alert(NSLocalizedString("settings.firstRun.reset.title", value: "Reset First-Run State?", comment: ""),
               isPresented: $showResetFirstRunConfirm) {
            Button(NSLocalizedString("common.cancel", value: "Cancel", comment: ""), role: .cancel) { }
            Button(NSLocalizedString("settings.firstRun.reset.confirm", value: "Reset", comment: ""), role: .destructive) {
                resetFirstRunState()
            }
        } message: {
            Text(NSLocalizedString("settings.firstRun.reset.message",
                                   value: "Onboarding flags will be cleared so the app tour and setup checklist appear again on next launch. No client data is affected.",
                                   comment: ""))
        }
    }

    // MARK: - Reusable pieces

    /// Branded header card showing business name + iCloud sync state.
    private var headerCard: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(DS.ColorToken.primary.opacity(0.15))
                .frame(width: 52, height: 52)
                .overlay(
                    Image(systemName: "pawprint.fill")
                        .font(.title2)
                        .foregroundStyle(DS.ColorToken.primary)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(appSettings.businessName.isEmpty
                     ? NSLocalizedString("settings.header.placeholder", value: "Your Business", comment: "")
                     : appSettings.businessName)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                HStack(spacing: 6) {
                    Image(systemName: cloudKitMonitor.statusIconName)
                        .font(.caption2)
                        .foregroundStyle(cloudKitTintColor)
                    Text(cloudKitMonitor.accountState.displayLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("•").font(.caption).foregroundStyle(.secondary)
                    Text(syncStateLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
    }

    /// Consistent Form-section header: small icon + title, no upper-case
    /// transform.
    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(DS.ColorToken.primary)
            Text(title)
        }
        .textCase(nil)
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

    #if os(iOS)
    private var notificationStatusRow: some View {
        HStack(spacing: 12) {
            Image(systemName: notificationAuthState.icon)
                .font(.body)
                .foregroundStyle(notificationAuthState.tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString("settings.notifications", value: "Notifications", comment: ""))
                    .font(.body)
                Text(notificationAuthState.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button {
                openSystemNotificationSettings()
            } label: {
                Text(NSLocalizedString("settings.notifications.manage", value: "Manage", comment: ""))
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("settings.notificationsManage")
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settings.notificationsRow")
    }
    #endif

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
        case .error:   return NSLocalizedString("cloudkit.status.error",   value: "Sync error", comment: "")
        case .idle:    return NSLocalizedString("cloudkit.status.idle",    value: "Idle",      comment: "")
        }
    }

    private var appVersionString: String {
        let dict = Bundle.main.infoDictionary ?? [:]
        let version = (dict["CFBundleShortVersionString"] as? String) ?? "—"
        let build = (dict["CFBundleVersion"] as? String) ?? "—"
        return "\(version) (\(build))"
    }

    private var securityStatusCard: some View {
        ZStack {
            LinearGradient(
                colors: [
                    effectiveLockEnabled ? DS.ColorToken.success : Color.gray,
                    effectiveLockEnabled ? Color.green.opacity(0.8) : Color.gray.opacity(0.8)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            HStack(spacing: 12) {
                Circle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 48, height: 48)
                    .overlay(
                        Image(systemName: effectiveLockEnabled ? "checkmark.shield.fill" : "lock.open.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                    )
                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString(effectiveLockEnabled ? "settings.security.status.active_title" : "settings.security.status.inactive_title", comment: ""))
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(NSLocalizedString(effectiveLockEnabled ? "settings.security.status.active_subtitle" : "settings.security.status.inactive_subtitle", comment: ""))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.9))
                }
                Spacer()
            }
            .padding(16)
        }
        .padding(.horizontal)
        .frame(height: 96)
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

    // MARK: - Actions

    private var effectiveLockEnabled: Bool {
        lockEnabledOverride ?? appSettings.isLockEnabled
    }

    private func syncLockToggleProxy() {
        lockToggleProxy = effectiveLockEnabled
    }

    private func handleLockToggleChange(from oldValue: Bool, to newValue: Bool) {
        guard oldValue != newValue else { return }

        if !newValue && effectiveLockEnabled {
            // Keep the switch visually enabled until the user confirms the
            // destructive action.
            lockEnabledOverride = true
            showDisableLockConfirm = true
            lockToggleProxy = true
        } else {
            lockEnabledOverride = newValue
            appSettings.isLockEnabled = newValue
        }
    }

    private func handleLockToggleTap() {
        if effectiveLockEnabled {
            lockEnabledOverride = true
            lockToggleProxy = true
            showDisableLockConfirm = true
        } else {
            lockEnabledOverride = true
            appSettings.isLockEnabled = true
            lockToggleProxy = true
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

    /// Clears all first-run / onboarding flags so the new-user tour and
    /// dashboard checklist re-appear on next launch. Does not touch any
    /// client, pet, visit, or financial data.
    private func resetFirstRunState() {
        appSettings.hasConfiguredPrices = false
        appSettings.hasAddedFirstClient = false
        appSettings.hasCompletedFirstVisit = false
        appSettings.isChecklistDismissed = false
        appSettings.hasSeenAppTour = false
        HapticManager.notify(.success)
    }

    private func refreshNotificationStatus() {
        #if os(iOS)
        Task { @MainActor in
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            switch settings.authorizationStatus {
            case .authorized:    notificationAuthState = .authorized
            case .denied:        notificationAuthState = .denied
            case .notDetermined: notificationAuthState = .notDetermined
            case .provisional:   notificationAuthState = .provisional
            case .ephemeral:     notificationAuthState = .ephemeral
            @unknown default:    notificationAuthState = .unknown
            }
        }
        #else
        notificationAuthState = .authorized
        #endif
    }

    private func openSystemNotificationSettings() {
        #if os(iOS)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
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
