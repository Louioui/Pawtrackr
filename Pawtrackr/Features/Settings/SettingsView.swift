//
//  SettingsView.swift
//  Pawtrackr
//
//  Created by Gemini on 9/15/25.
//

import SwiftUI
import SwiftData
import OSLog
#if os(iOS)
import UserNotifications
import UIKit
#elseif os(macOS)
import AppKit
#endif

private func settingsLocalized(_ key: String, value: String) -> String {
    AppLocalization.localized(key, value: value)
}

enum SettingSection: String, CaseIterable, Identifiable {
    case business, preferences, security, dataExport, icloud, help, devices, about
    var id: String { rawValue }
    var localizationKey: String {
        switch self {
        case .business: return "settings.section.business"
        case .preferences: return "settings.section.preferences"
        case .security: return "settings.section.security"
        case .dataExport: return "settings.section.export"
        case .icloud: return "settings.section.icloud"
        case .help: return "settings.section.help"
        case .devices: return "settings.section.devices"
        case .about: return "settings.section.about"
        }
    }

    var title: LocalizedStringKey {
        LocalizedStringKey(localizationKey)
    }
    
    var icon: String {
        switch self {
        case .business: return "building.2.fill"
        case .preferences: return "slider.horizontal.3"
        case .security: return "lock.shield.fill"
        case .dataExport: return "square.and.arrow.up"
        case .icloud: return "icloud.fill"
        case .help: return "questionmark.circle.fill"
        case .devices: return "iphone.gen3.radiowaves.left.and.right"
        case .about: return "info.circle.fill"
        }
    }

    var walkthroughAnchorID: WalkthroughAnchorID? {
        switch self {
        case .business:
            return .setBusiness
        case .security:
            return .setSecurity
        case .dataExport:
            return .setData
        case .icloud:
            return .setICloud
        case .about:
            return .setAbout
        case .preferences, .help, .devices:
            return nil
        }
    }
}

enum SettingsAdaptiveLayout {
    static let maxReadableContentWidth: CGFloat = 940
    static let compactNavigatorThreshold: CGFloat = 700
    static let macSidebarMinWidth: CGFloat = 132
    static let macSidebarIdealWidth: CGFloat = 158
    static let macSidebarMaxWidth: CGFloat = 188

    static func usesCompactSettingsNavigator(availableWidth: CGFloat) -> Bool {
        availableWidth < compactNavigatorThreshold
    }

    static func detailHorizontalPadding(for availableWidth: CGFloat) -> CGFloat {
        if availableWidth < 520 {
            return 16
        }
        if availableWidth < 820 {
            return 20
        }
        return 30
    }

    static func detailVerticalPadding(for availableWidth: CGFloat) -> CGFloat {
        availableWidth < 520 ? 18 : 30
    }

    static func contentMaxWidth(for availableWidth: CGFloat) -> CGFloat {
        let usableWidth = max(0, availableWidth - detailHorizontalPadding(for: availableWidth) * 2)
        return min(maxReadableContentWidth, usableWidth)
    }
}

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var appSettings
    @State private var selection: SettingSection? = .business
    
    // State needed for sub-views
    @State private var showChangePIN = false
    @State private var pinChangeError: String? = nil
    @State private var showResetFirstRunConfirm = false
    @State private var showWipeConfirm = false
    @State private var showDiagnostics = false

    var body: some View {
        #if os(macOS)
        GeometryReader { proxy in
            if SettingsAdaptiveLayout.usesCompactSettingsNavigator(availableWidth: proxy.size.width) {
                compactMacSettings
            } else {
                regularMacSettings
            }
        }
        #else
        NavigationStack {
            List(SettingSection.allCases) { section in
                NavigationLink {
                    SettingsDetailView(section: section,
                                       showChangePIN: $showChangePIN,
                                       showResetFirstRunConfirm: $showResetFirstRunConfirm,
                                       showWipeConfirm: $showWipeConfirm,
                                       showDiagnostics: $showDiagnostics)
                } label: {
                    Label(section.title, systemImage: section.icon)
                }
                .optionalWalkthroughAnchor(section.walkthroughAnchorID)
                .accessibilityIdentifier("settings.section.\(section.rawValue)")
            }
            .navigationTitle(Text("settings.title"))
        }
        #endif
    }

    #if os(macOS)
    private var selectedSectionBinding: Binding<SettingSection> {
        Binding {
            selection ?? .business
        } set: { newValue in
            selection = newValue
        }
    }

    private var regularMacSettings: some View {
        NavigationSplitView {
            settingsSectionList
                .navigationTitle(Text("settings.title"))
                .navigationSplitViewColumnWidth(
                    min: SettingsAdaptiveLayout.macSidebarMinWidth,
                    ideal: SettingsAdaptiveLayout.macSidebarIdealWidth,
                    max: SettingsAdaptiveLayout.macSidebarMaxWidth
                )
        } detail: {
            settingsDetail
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var compactMacSettings: some View {
        VStack(spacing: 0) {
            Picker(settingsLocalized("settings.title", value: "Settings"), selection: selectedSectionBinding) {
                ForEach(SettingSection.allCases) { section in
                    Label(section.title, systemImage: section.icon)
                        .tag(section)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()
            settingsDetail
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var settingsSectionList: some View {
        List(SettingSection.allCases, selection: $selection) { section in
            NavigationLink(value: section) {
                Label(section.title, systemImage: section.icon)
                    .font(.system(.body, design: .rounded).weight(.medium))
            }
            .optionalWalkthroughAnchor(section.walkthroughAnchorID)
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private var settingsDetail: some View {
        if let selection {
            SettingsDetailView(section: selection,
                               showChangePIN: $showChangePIN,
                               showResetFirstRunConfirm: $showResetFirstRunConfirm,
                               showWipeConfirm: $showWipeConfirm,
                               showDiagnostics: $showDiagnostics)
        } else {
            ContentUnavailableView(LocalizedStringKey("settings.select_setting"), systemImage: "gear")
        }
    }
    #endif
}

private struct SettingsDetailView: View {
    let section: SettingSection
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var appSettings
    @Binding var showChangePIN: Bool
    @Binding var showResetFirstRunConfirm: Bool
    @Binding var showWipeConfirm: Bool
    @Binding var showDiagnostics: Bool
    
    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(section.title)
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    content
                }
                .frame(maxWidth: SettingsAdaptiveLayout.contentMaxWidth(for: proxy.size.width), alignment: .leading)
                .padding(.horizontal, SettingsAdaptiveLayout.detailHorizontalPadding(for: proxy.size.width))
                .padding(.vertical, SettingsAdaptiveLayout.detailVerticalPadding(for: proxy.size.width))
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .sheet(isPresented: $showChangePIN) {
            ChangePINSheet(isPresented: $showChangePIN)
                .environment(appSettings)
        }
        .sheet(isPresented: $showDiagnostics) {
            NavigationStack {
                CloudKitDiagnosticsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(settingsLocalized("common.done", value: "Done")) { showDiagnostics = false }
                        }
                    }
            }
        }
        .alert(
            settingsLocalized("settings.reset_guide.title", value: "Replay Getting Started?"),
            isPresented: $showResetFirstRunConfirm
        ) {
            Button(settingsLocalized("common.cancel", value: "Cancel"), role: .cancel) {}
            Button(settingsLocalized("settings.reset_guide.confirm", value: "Replay")) {
                appSettings.replayGettingStarted()
            }
        } message: {
            Text(settingsLocalized(
                "settings.reset_guide.message",
                value: "This re-shows the new-user tour and dashboard checklist. Your business settings, clients, and visits are not affected."
            ))
        }
        .alert(
            settingsLocalized("settings.wipe.title", value: "Wipe Everything & Start Fresh?"),
            isPresented: $showWipeConfirm
        ) {
            Button(settingsLocalized("common.cancel", value: "Cancel"), role: .cancel) {}
            Button(settingsLocalized("settings.wipe.confirm", value: "Erase Everything"), role: .destructive) {
                performWipe()
            }
        } message: {
            Text(settingsLocalized(
                "settings.wipe.message",
                value: "This permanently erases every client, pet, visit, payment, inventory item, and report — including the demo data — and cannot be undone. The wipe also syncs to iCloud and your other devices. Your business profile and service menu are kept."
            ))
        }
    }

    /// Erases operational data and re-arms the getting-started checklist. Runs on
    /// the main context; live lists react to the deletions and empty out.
    private func performWipe() {
        do {
            try DataReset.wipeOperationalData(in: modelContext)
            appSettings.resetForFreshStart()
            #if os(iOS)
            HapticManager.notify(.success)
            #endif
        } catch {
            Logger.database.error("Start Fresh wipe failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .business: BusinessSectionView(appSettings: appSettings)
        case .preferences: PreferencesSectionView(appSettings: appSettings)
        case .security: SecuritySectionView(appSettings: appSettings, showChangePIN: $showChangePIN)
        case .dataExport: DataExportSectionView(modelContext: modelContext)
        case .icloud: ICloudSectionView(showDiagnostics: $showDiagnostics)
        case .help: HelpSectionView(modelContext: modelContext)
        case .devices: DevicesHealthView()
        case .about: AboutSectionView(showResetFirstRunConfirm: $showResetFirstRunConfirm, showWipeConfirm: $showWipeConfirm)
        }
    }
}

private struct DataExportSectionView: View {
    let modelContext: ModelContext
    @State private var isExportingClients = false
    @State private var isExportingVisits = false
    @State private var exportDocument: ExportDocument?
    @State private var exportError: String?

    var body: some View {
        CardView {
            Button {
                runExport(kind: .clients)
            } label: {
                Label(settingsLocalized("settings.export.clients_csv", value: "Export Clients (CSV)"), systemImage: "person.3.sequence.fill")
            }
            .accessibilityIdentifier("settings.exportClients")
            .disabled(isExportingClients || isExportingVisits)
            
            Button {
                runExport(kind: .visits)
            } label: {
                Label(settingsLocalized("settings.export.visits_csv", value: "Export Visits (CSV)"), systemImage: "calendar.badge.clock")
            }
            .accessibilityIdentifier("settings.exportVisits")
            .disabled(isExportingClients || isExportingVisits)

            if isExportingClients || isExportingVisits {
                ProgressView(settingsLocalized("settings.export.preparing", value: "Preparing export..."))
            }

            if let exportDocument {
                ShareLink(
                    item: exportDocument,
                    preview: SharePreview(exportDocument.filename, icon: Image(systemName: "doc.text.fill"))
                ) {
                    Label(
                        String(format: settingsLocalized("settings.export.share_fmt", value: "Share %@"), exportDocument.filename),
                        systemImage: "square.and.arrow.up"
                    )
                }
                .buttonStyle(.borderedProminent)
            }

            if let exportError {
                Text(exportError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    
    enum ExportKind { case clients, visits }
    private func runExport(kind: ExportKind) {
        exportError = nil
        exportDocument = nil

        switch kind {
        case .clients:
            isExportingClients = true
        case .visits:
            isExportingVisits = true
        }

        defer {
            isExportingClients = false
            isExportingVisits = false
        }

        do {
            switch kind {
            case .clients:
                exportDocument = try ExportService.shared.exportClientsToCSV(modelContext: modelContext)
            case .visits:
                exportDocument = try ExportService.shared.exportVisitsToCSV(modelContext: modelContext)
            }
        } catch {
            exportError = String(format: settingsLocalized("settings.export.failed_fmt", value: "Export failed: %@"), error.localizedDescription)
        }
    }
}

private struct ICloudSectionView: View {
    @Binding var showDiagnostics: Bool
    @State private var monitor = CloudKitMonitor.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            CardView {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: monitor.statusIconName)
                        .font(.title2)
                        .foregroundStyle(statusColor)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(monitor.healthHeadline)
                            .font(.headline)
                        Text(monitor.healthDetail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()
                }

                Divider()

                SettingsInfoRow(title: settingsLocalized("settings.icloud.account", value: "Account"), value: monitor.accountState.displayLabel)
                SettingsInfoRow(title: settingsLocalized("settings.icloud.network", value: "Network"), value: monitor.networkState.displayLabel)
                SettingsInfoRow(title: settingsLocalized("settings.icloud.last_sync", value: "Last Sync"), value: monitor.lastSyncSummary)

                if let pending = monitor.pendingChangesSummary {
                    SettingsInfoRow(title: settingsLocalized("settings.icloud.pending_changes", value: "Pending Changes"), value: pending)
                }

                Button {
                    Task { await monitor.forceSync() }
                } label: {
                    Label(manualCheckTitle, systemImage: monitor.canForceSync ? "arrow.clockwise.icloud" : "timer")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!monitor.canForceSync)
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    showDiagnostics = true
                } label: {
                    Label(settingsLocalized("settings.icloud.open_diagnostics", value: "Open iCloud Diagnostics"), systemImage: "stethoscope")
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let lastError = monitor.lastErrorMessage {
                CardView {
                    Label(settingsLocalized("settings.icloud.sync_attention", value: "Sync Attention"), systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(.orange)
                    Text(lastError)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var statusColor: Color {
        switch monitor.statusTint {
        case .success: return .green
        case .neutral: return .blue
        case .warning: return .orange
        case .danger: return .red
        }
    }

    private var manualCheckTitle: String {
        guard !monitor.canForceSync else {
            return settingsLocalized("settings.icloud.check", value: "Check iCloud")
        }
        return String(
            format: settingsLocalized("cloudkit.action.check_status_wait_fmt", value: "Check again in %ds"),
            monitor.manualCheckRemainingSeconds
        )
    }
}

private struct SettingsInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value)
                .multilineTextAlignment(.trailing)
                .lineLimit(3)
                .minimumScaleFactor(0.75)
        }
        .font(.subheadline)
    }
}

private struct HelpSectionView: View {
    let modelContext: ModelContext
    @State private var isPreparingReport = false
    @State private var supportMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            CardView {
                Label(settingsLocalized("settings.help.support_title", value: "Support Toolkit"), systemImage: "lifepreserver")
                    .font(.headline)

                Text(settingsLocalized(
                    "settings.help.support_detail",
                    value: "Collect a local support report before troubleshooting sync, exports, or device setup."
                ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                Button {
                    Task { await copySupportReport() }
                } label: {
                    Label(settingsLocalized("settings.help.copy_report", value: "Copy Support Report"), systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isPreparingReport)

                if isPreparingReport {
                    ProgressView(settingsLocalized("settings.help.preparing_report", value: "Preparing report..."))
                }

                if let supportMessage {
                    Text(supportMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            CardView {
                HelpTopicRow(
                    icon: "icloud.fill",
                    title: settingsLocalized("settings.help.icloud_title", value: "iCloud Sync"),
                    detail: settingsLocalized(
                        "settings.help.icloud_detail",
                        value: "Use the iCloud section to check account status, pending changes, and diagnostics. On real devices, confirm the Apple Account is signed in and iCloud Drive is enabled."
                    )
                )
                HelpTopicRow(
                    icon: "printer.fill",
                    title: settingsLocalized("settings.help.hardware_title", value: "Printers & Hardware"),
                    detail: settingsLocalized(
                        "settings.help.hardware_detail",
                        value: "Bluetooth receipt printing requires a physical iPad or iPhone and supported salon hardware. The simulator cannot discover printers."
                    )
                )
                HelpTopicRow(
                    icon: "square.and.arrow.up",
                    title: settingsLocalized("settings.help.exports_title", value: "Exports & Backups"),
                    detail: settingsLocalized(
                        "settings.help.exports_detail",
                        value: "Use Data Export to create client or visit CSV files before major cleanup, migrations, or support sessions."
                    )
                )
            }
        }
    }

    @MainActor
    private func copySupportReport() async {
        isPreparingReport = true
        defer { isPreparingReport = false }

        let report = await SupportService.shared.generateReport(context: modelContext)
        copyToClipboard(report.content)
        supportMessage = settingsLocalized("settings.help.report_copied", value: "Support report copied.")
    }

    private func copyToClipboard(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

private struct HelpTopicRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BusinessSectionView: View {
    @Bindable var appSettings: AppSettings
    var body: some View {
        CardView {
            TextField(settingsLocalized("settings.business.name", value: "Business Name"), text: $appSettings.businessName)
                .textFieldStyle(.roundedBorder)
            TextField(settingsLocalized("settings.business.currency_symbol", value: "Currency Symbol"), text: $appSettings.currencySymbol)
                .textFieldStyle(.roundedBorder)
        }
    }
}

private struct PreferencesSectionView: View {
    @Bindable var appSettings: AppSettings

    var body: some View {
        CardView {
            Picker(selection: $appSettings.appLanguageOverride) {
                ForEach(AppLanguageOverride.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            } label: {
                Label(settingsLocalized("settings.preferences.language", value: "Language"), systemImage: "globe")
            }

            Picker(selection: $appSettings.preferredColorScheme) {
                ForEach(AppColorScheme.allCases) { scheme in
                    Text(scheme.displayName).tag(scheme)
                }
            } label: { Label(settingsLocalized("settings.preferences.appearance", value: "Appearance"), systemImage: "circle.lefthalf.filled") }

            Picker(selection: $appSettings.defaultLaunchTab) {
                ForEach(NavigationItem.allCases) { item in
                    Label(item.label, systemImage: item.icon)
                        .tag(item.rawValue)
                }
            } label: {
                Label(settingsLocalized("settings.preferences.default_launch", value: "Default Launch Tab"), systemImage: "rectangle.stack.fill")
            }

            SettingsLabeledField(
                title: settingsLocalized("settings.preferences.device_name", value: "Device Name"),
                systemImage: "iphone.gen3"
            ) {
                TextField(settingsLocalized("settings.preferences.device_name_placeholder", value: "Reception iPad"), text: $appSettings.deviceName)
                    .textFieldStyle(.roundedBorder)
            }

            ColorPicker(
                selection: brandColorBinding,
                supportsOpacity: false
            ) {
                Label(settingsLocalized("settings.preferences.brand_color", value: "Brand Color"), systemImage: "paintpalette.fill")
            }

            HStack {
                Text(settingsLocalized("settings.preferences.brand_color_hex", value: "Brand Color Hex"))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(appSettings.brandColorHex.uppercased())
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Toggle(isOn: $appSettings.hapticsEnabled) {
                Label(settingsLocalized("settings.preferences.haptics", value: "Haptic Feedback"), systemImage: "hand.tap.fill")
            }

            Toggle(isOn: $appSettings.optimizeMediaForICloud) {
                Label(settingsLocalized("settings.preferences.optimize_media", value: "Optimize Media for iCloud"), systemImage: "photo.on.rectangle.angled")
            }

            Text(settingsLocalized(
                "settings.preferences.optimize_media_detail",
                value: "Keeps photo storage lighter while preserving synced originals where available."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var brandColorBinding: Binding<Color> {
        Binding {
            Color(hex: appSettings.brandColorHex) ?? DS.ColorToken.primary
        } set: { newColor in
            if let hex = newColor.settingsHexRGB {
                appSettings.brandColorHex = hex
            }
        }
    }
}

private struct SecuritySectionView: View {
    @Bindable var appSettings: AppSettings
    @Binding var showChangePIN: Bool
    @State private var showDisableLockConfirm = false
    /// True while we're routing the user to set a PIN before enabling the lock.
    @State private var pendingEnableLock = false

    var body: some View {
        CardView {
            Toggle(isOn: lockEnabledBinding) {
                Label(settingsLocalized("settings.security.enable_lock", value: "Enable App Lock"), systemImage: "lock.shield.fill")
            }
            .accessibilityIdentifier("settings.appLockToggle")
            .onChange(of: showChangePIN) { _, isPresented in
                // Sheet dismissed after we routed here to set a first PIN: enable
                // the lock only if a PIN was actually chosen.
                guard !isPresented, pendingEnableLock else { return }
                pendingEnableLock = false
                if appSettings.lastPINChangeDate != nil {
                    appSettings.isLockEnabled = true
                }
            }

            Toggle(isOn: $appSettings.isBiometricLockEnabled) {
                Label(settingsLocalized("settings.security.biometric_unlock", value: "Biometric Unlock"), systemImage: "faceid")
            }
            .accessibilityIdentifier("settings.biometricLockToggle")
            .disabled(!appSettings.isLockEnabled)

            Toggle(isOn: $appSettings.autoLockOnBackground) {
                Label(settingsLocalized("settings.security.lock_on_background", value: "Lock When App Closes"), systemImage: "rectangle.portrait.and.arrow.right")
            }
            .accessibilityIdentifier("settings.autoLockOnBackgroundToggle")
            .disabled(!appSettings.isLockEnabled)

            Toggle(isOn: $appSettings.autoLockAfterInactivity) {
                Label(settingsLocalized("settings.security.lock_after_inactivity", value: "Lock After Inactivity"), systemImage: "timer")
            }
            .accessibilityIdentifier("settings.autoLockAfterInactivityToggle")
            .disabled(!appSettings.isLockEnabled)

            Stepper(value: $appSettings.idleLockMinutes, in: 1...60) {
                HStack {
                    Label(settingsLocalized("settings.security.idle_minutes", value: "Idle Timeout"), systemImage: "hourglass")
                    Spacer()
                    Text(String(format: settingsLocalized("settings.security.idle_minutes_value_fmt", value: "%d min"), appSettings.idleLockMinutes))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .disabled(!appSettings.isLockEnabled || !appSettings.autoLockAfterInactivity)

            Text(String(format: settingsLocalized(
                "settings.security.lock_after_inactivity_detail_fmt",
                value: "When enabled, Pawtrackr locks after %d minutes without interaction."
            ), appSettings.idleLockMinutes))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            if appSettings.isLockEnabled {
                Button(settingsLocalized("settings.pin.change", value: "Change PIN")) { showChangePIN = true }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("settings.changePIN")
            }
        }
        .alert(
            settingsLocalized("settings.security.disable_lock_title", value: "Disable App Lock?"),
            isPresented: $showDisableLockConfirm
        ) {
            Button(settingsLocalized("common.cancel", value: "Cancel"), role: .cancel) {}
            Button(settingsLocalized("settings.security.disable_lock_confirm", value: "Disable"), role: .destructive) {
                appSettings.isLockEnabled = false
            }
        } message: {
            Text(settingsLocalized(
                "settings.security.disable_lock_message",
                value: "Pawtrackr will stop requiring your PIN when the app opens or returns to the foreground."
            ))
        }
    }

    private var lockEnabledBinding: Binding<Bool> {
        Binding {
            appSettings.isLockEnabled
        } set: { isEnabled in
            if isEnabled {
                if appSettings.lastPINChangeDate == nil {
                    // Passcode-free setup: never had a PIN. Make the user set one
                    // first so the lock can't fall back to the default code.
                    pendingEnableLock = true
                    showChangePIN = true
                } else {
                    appSettings.isLockEnabled = true
                }
            } else {
                showDisableLockConfirm = true
            }
        }
    }
}

private struct SettingsLabeledField<Content: View>: View {
    let title: String
    let systemImage: String
    let content: Content

    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.medium))
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AboutSectionView: View {
    @Binding var showResetFirstRunConfirm: Bool
    @Binding var showWipeConfirm: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            CardView {
                HStack {
                    Text(settingsLocalized("settings.about.version", value: "Version"))
                    Spacer()
                    Text(versionText)
                        .foregroundStyle(.secondary)
                }

                Divider()

                Button {
                    showResetFirstRunConfirm = true
                } label: {
                    Label(settingsLocalized("settings.about.replay_guide", value: "Replay Getting Started"), systemImage: "sparkles")
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Destructive "Start Fresh": clears the demo (and anything entered
            // while exploring) so the operator can begin real business clean.
            CardView {
                Label(settingsLocalized("settings.wipe.section_title", value: "Start Fresh"), systemImage: "trash")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)

                Text(settingsLocalized("settings.wipe.section_caption", value: "Erase all clients, pets, visits, and history (including the demo) and begin with an empty workspace. Your business profile and service menu are kept."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button(role: .destructive) {
                    showWipeConfirm = true
                } label: {
                    Label(settingsLocalized("settings.wipe.button", value: "Wipe & Start Fresh"), systemImage: "exclamationmark.triangle.fill")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
    }

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String
        guard let build, !build.isEmpty else { return version }
        return "\(version) (\(build))"
    }
}

private struct CardView<Content: View>: View {
    let content: Content
    @State private var isHovering = false
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    
    var body: some View {
        VStack(spacing: 16) { content }
            .padding()
            .background(.background, in: RoundedRectangle(cornerRadius: 12))
            .shadow(color: Color.black.opacity(isHovering ? 0.1 : 0.05), radius: isHovering ? 8 : 5, x: 0, y: 2)
            .scaleEffect(isHovering ? 1.01 : 1.0)
            .onHover { isHovering = $0 }
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHovering)
    }
}

private extension View {
    @ViewBuilder
    func optionalWalkthroughAnchor(_ id: WalkthroughAnchorID?) -> some View {
        if let id {
            walkthroughAnchor(id)
        } else {
            self
        }
    }
}

private extension Color {
    var settingsHexRGB: String? {
        #if os(iOS)
        let platformColor = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard platformColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        #elseif os(macOS)
        guard let platformColor = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        let red = platformColor.redComponent
        let green = platformColor.greenComponent
        let blue = platformColor.blueComponent
        #else
        return nil
        #endif

        return String(
            format: "#%02X%02X%02X",
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded())
        )
    }
}
