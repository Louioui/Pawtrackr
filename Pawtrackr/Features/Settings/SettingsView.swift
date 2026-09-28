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
    case business, preferences, loyalty, security, dataExport, icloud, help, devices, about
    var id: String { rawValue }
    var localizationKey: String {
        switch self {
        case .business: return "settings.section.business"
        case .preferences: return "settings.section.preferences"
        case .loyalty: return "settings.section.loyalty"
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

    var subtitle: String {
        switch self {
        case .business:
            return settingsLocalized("settings.section.business.subtitle", value: "Branding and receipt defaults used across checkout, exports, and customer-facing paperwork.")
        case .preferences:
            return settingsLocalized("settings.section.preferences.subtitle", value: "Tune the app for this workstation, from launch behavior to synced media handling.")
        case .loyalty:
            return settingsLocalized("settings.section.loyalty.subtitle", value: "Configure how visits earn points and which rewards your salon wants to offer.")
        case .security:
            return settingsLocalized("settings.section.security.subtitle", value: "Protect client records with PIN, biometric unlock, and automatic locking rules.")
        case .dataExport:
            return settingsLocalized("settings.section.export.subtitle", value: "Export operational data for reporting, backup review, or handoff outside Pawtrackr.")
        case .icloud:
            return settingsLocalized("settings.section.icloud.subtitle", value: "Check sync health, pending uploads, and diagnostics for this iCloud account.")
        case .help:
            return settingsLocalized("settings.section.help.subtitle", value: "Support tools and quick recovery guidance for day-to-day salon operation.")
        case .devices:
            return settingsLocalized("settings.section.devices.subtitle", value: "See which iPhones, iPads, and Macs are synced or currently active.")
        case .about:
            return settingsLocalized("settings.section.about.subtitle", value: "Version details, guided setup, and the protected fresh-start control.")
        }
    }
    
    var icon: String {
        switch self {
        case .business: return "building.2.fill"
        case .preferences: return "slider.horizontal.3"
        case .loyalty: return "star.circle.fill"
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
        case .preferences, .loyalty, .help, .devices:
            return nil
        }
    }

    static func walkthroughSection(for anchor: WalkthroughAnchorID?) -> SettingSection? {
        guard let anchor else { return nil }
        if anchor == .setStartFresh { return .about }
        return allCases.first { $0.walkthroughAnchorID == anchor }
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
    @Environment(WalkthroughController.self) private var walkthrough: WalkthroughController?
    @Environment(NavigationRouter.self) private var router
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
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
        .onChange(of: walkthrough?.currentStep?.anchor) { _, anchor in
            synchronizeWalkthroughSection(anchor)
        }
        #else
        // No inner NavigationStack — SettingsView already lives inside ContentView's
        // settings NavigationStack. Nesting one here made NavigationLink(value:)
        // resolve to the wrong stack, so rows went grey and never opened. The
        // value links + this navigationDestination register on the ambient stack
        // (router.settingsPath, a type-erased NavigationPath), and the tour drives
        // that same path to step into a section.
        List(SettingSection.allCases) { section in
            NavigationLink(value: section) {
                Label(section.title, systemImage: section.icon)
            }
            .accessibilityIdentifier("settings.section.\(section.rawValue)")
        }
        .navigationTitle(Text("settings.title"))
        .navigationDestination(for: SettingSection.self) { section in
            let detail = SettingsDetailView(section: section,
                                            showChangePIN: $showChangePIN,
                                            showResetFirstRunConfirm: $showResetFirstRunConfirm,
                                            showWipeConfirm: $showWipeConfirm,
                                            showDiagnostics: $showDiagnostics)
            // Re-host the guided-tour overlay ON the pushed Settings detail so the
            // `set*` spotlights (which live in SettingsDetailView) resolve on iPad:
            // the split-view detail-column overlay sits OUTSIDE this NavigationStack
            // and can't see pushed anchors. Compact (iPhone) keeps its single root
            // overlay, so this is a no-op there to avoid a double-dim.
            if horizontalSizeClass != .compact, let walkthrough {
                detail.walkthroughOverlay(walkthrough, scope: .detailContent)
            } else {
                detail
            }
        }
        .onChange(of: walkthrough?.currentStep?.anchor) { _, anchor in
            synchronizeWalkthroughSection(anchor)
        }
        #endif
    }

    private func synchronizeWalkthroughSection(_ anchor: WalkthroughAnchorID?) {
        guard walkthrough?.currentStep?.surface == .settings else { return }

        #if os(macOS)
        if let section = SettingSection.walkthroughSection(for: anchor) {
            selection = section
        }
        #else
        if anchor == .settings {
            if !router.settingsPath.isEmpty { router.settingsPath = NavigationPath() }
        } else if let section = SettingSection.walkthroughSection(for: anchor) {
            router.settingsPath = NavigationPath([section])
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
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private var settingsDetail: some View {
        if let selection {
            let detail = SettingsDetailView(section: selection,
                                            showChangePIN: $showChangePIN,
                                            showResetFirstRunConfirm: $showResetFirstRunConfirm,
                                            showWipeConfirm: $showWipeConfirm,
                                            showDiagnostics: $showDiagnostics)
            if let walkthrough {
                detail.walkthroughOverlay(walkthrough, scope: .detailContent)
            } else {
                detail
            }
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
    @Environment(WalkthroughController.self) private var walkthrough: WalkthroughController?
    @Binding var showChangePIN: Bool
    @Binding var showResetFirstRunConfirm: Bool
    @Binding var showWipeConfirm: Bool
    @Binding var showDiagnostics: Bool
    @State private var showWipeBlockedAlert = false
    @State private var storeRestoreClientCount: Int?
    @AppStorage(DataSafetyMonitor.suspectedDataLossKey) private var dataLossSuspected = false

    private static let walkthroughAnchors: Set<WalkthroughAnchorID> = [
        .setBusiness,
        .setSecurity,
        .setData,
        .setICloud,
        .setAbout,
        .setStartFresh
    ]
    
    var body: some View {
        GeometryReader { proxy in
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(section.title)
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        Text(section.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, -12)

                        content
                            .optionalWalkthroughTarget(section == .about ? nil : section.walkthroughAnchorID)
                    }
                    .frame(maxWidth: SettingsAdaptiveLayout.contentMaxWidth(for: proxy.size.width), alignment: .leading)
                    .padding(.horizontal, SettingsAdaptiveLayout.detailHorizontalPadding(for: proxy.size.width))
                    .padding(.vertical, SettingsAdaptiveLayout.detailVerticalPadding(for: proxy.size.width))
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .onAppear {
                    scrollToWalkthroughAnchorIfNeeded(walkthrough?.currentStep?.anchor, proxy: scrollProxy)
                }
                .onChange(of: walkthrough?.currentStep?.anchor) { _, anchor in
                    scrollToWalkthroughAnchorIfNeeded(anchor, proxy: scrollProxy)
                }
            }
        }
        .sheet(isPresented: $showChangePIN) {
            ChangePINSheet(isPresented: $showChangePIN)
                .environment(appSettings)
        }
        .sheet(isPresented: Binding(
            get: { storeRestoreClientCount != nil },
            set: { if !$0 { storeRestoreClientCount = nil } }
        )) {
            StoreRestoreView(currentClientCount: storeRestoreClientCount ?? 0)
        }
        .sheet(isPresented: $showDiagnostics) {
            NavigationStack {
                CloudKitDiagnosticsView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(settingsLocalized("common.close", value: "Close")) { showDiagnostics = false }
                                .keyboardShortcut(.cancelAction)
                        }
                    }
            }
            .frame(minWidth: 560, idealWidth: 680, maxWidth: 760, minHeight: 520, idealHeight: 700, maxHeight: 820)
        }
        .alert(
            settingsLocalized("settings.reset_guide.title", value: "Replay Getting Started?"),
            isPresented: $showResetFirstRunConfirm
        ) {
            Button(settingsLocalized("common.cancel", value: "Cancel"), role: .cancel) {}
            Button(settingsLocalized("settings.reset_guide.confirm", value: "Replay")) {
                replayGettingStarted()
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
        .alert(
            settingsLocalized("data_safety.wipe_blocked.title", value: "Start Fresh is locked"),
            isPresented: $showWipeBlockedAlert
        ) {
            Button(settingsLocalized("common.ok", value: "OK"), role: .cancel) {}
        } message: {
            Text(settingsLocalized(
                "data_safety.wipe_blocked.message",
                value: "Pawtrackr detected that client data may be missing after an update. Export or recover the data before using Start Fresh, because that wipe can sync deletions to iCloud."
            ))
        }
    }

    private func scrollToWalkthroughAnchorIfNeeded(_ anchor: WalkthroughAnchorID?, proxy: ScrollViewProxy) {
        guard let anchor, Self.walkthroughAnchors.contains(anchor) else { return }

        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.35)) {
                proxy.scrollTo(anchor, anchor: .center)
            }
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(420))
            guard walkthrough?.currentStep?.anchor == anchor else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                proxy.scrollTo(anchor, anchor: .center)
            }
        }
    }

    /// Erases operational data and re-arms the getting-started checklist. Runs on
    /// the main context; live lists react to the deletions and empty out.
    private func performWipe() {
        guard !dataLossSuspected else {
            showWipeBlockedAlert = true
            return
        }

        do {
            try DataReset.wipeOperationalData(in: modelContext)
            DataSafetyMonitor.clearAfterIntentionalWipe()
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
        case .loyalty: LoyaltyManagementView()
        case .security: SecuritySectionView(appSettings: appSettings, showChangePIN: $showChangePIN)
        case .dataExport: DataExportSectionView(modelContext: modelContext) {
            storeRestoreClientCount = (try? modelContext.fetchCount(FetchDescriptor<Client>())) ?? 0
        }
        case .icloud: ICloudSectionView(showDiagnostics: $showDiagnostics)
        case .help: HelpSectionView(modelContext: modelContext)
        case .devices: DevicesHealthView()
        case .about: AboutSectionView(
            showResetFirstRunConfirm: $showResetFirstRunConfirm,
            showWipeConfirm: $showWipeConfirm,
            dataLossSuspected: dataLossSuspected
        )
        }
    }

    private func replayGettingStarted() {
        NotificationCenter.default.post(name: .replayGettingStartedRequested, object: nil)
    }
}

private struct DataExportSectionView: View {
    let modelContext: ModelContext
    let onRestoreBackup: () -> Void
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

            Button(action: onRestoreBackup) {
                Label(settingsLocalized("settings.restore_backup", value: "Restore from On-Device Backup"), systemImage: "clock.arrow.circlepath")
            }
            .accessibilityIdentifier("settings.restoreBackup")

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
    @State private var isCheckingICloud = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            CardView {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: monitor.statusIconName)
                        .font(.title2)
                        .foregroundStyle(statusColor)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(monitor.healthHeadline)
                                .font(.headline)
                                .layoutPriority(1)

                            ICloudStatusPill(title: statusTitle, tint: statusColor)
                        }

                        Text(monitor.healthDetail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()
                }

                Divider()

                VStack(spacing: 10) {
                    SettingsInfoRow(title: settingsLocalized("settings.icloud.account", value: "Account"), value: monitor.accountState.displayLabel)
                    SettingsInfoRow(title: settingsLocalized("settings.icloud.network", value: "Network"), value: monitor.networkState.displayLabel)
                    // Only an upload iCloud accepted counts as a backup; downloads
                    // get their own row so one can't pass for the other.
                    SettingsInfoRow(title: settingsLocalized("settings.icloud.last_backup", value: "Last iCloud backup"), value: monitor.lastBackupValue)
                    SettingsInfoRow(title: settingsLocalized("settings.icloud.last_download", value: "Last download"), value: monitor.lastDownloadValue)

                    if let pending = monitor.pendingChangesSummary {
                        SettingsInfoRow(title: settingsLocalized("settings.icloud.pending_changes", value: "Pending Changes"), value: pending)
                    }
                }

                if !monitor.healthIssues.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(monitor.healthIssues.prefix(3)) { issue in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: issueIconName(for: issue.severity))
                                    .foregroundStyle(issueTint(for: issue.severity))
                                    .frame(width: 18)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(issue.title)
                                        .font(.caption.weight(.semibold))
                                    Text(issue.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }

                Divider()

                HStack(spacing: 10) {
                    Button {
                        Task { await runICloudCheck() }
                    } label: {
                        Label(manualCheckTitle, systemImage: manualCheckIcon)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isCheckingICloud || !monitor.canForceSync)

                    Button {
                        showDiagnostics = true
                    } label: {
                        Label(settingsLocalized("settings.icloud.open_diagnostics", value: "Open iCloud Diagnostics"), systemImage: "stethoscope")
                    }
                    .buttonStyle(.bordered)
                }
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

    @MainActor
    private func runICloudCheck() async {
        guard !isCheckingICloud else { return }
        isCheckingICloud = true
        defer { isCheckingICloud = false }

        await monitor.forceSync()
        monitor.updateDeviceMetadata()
        monitor.cleanupStalePresence()
    }

    private var statusColor: Color {
        switch monitor.statusTint {
        case .success: return .green
        case .neutral: return .blue
        case .warning: return .orange
        case .danger: return .red
        }
    }

    private var statusTitle: String {
        switch monitor.statusTint {
        case .success:
            return settingsLocalized("settings.icloud.status.healthy", value: "Healthy")
        case .neutral:
            return settingsLocalized("settings.icloud.status.checking", value: "Checking")
        case .warning:
            return settingsLocalized("settings.icloud.status.needs_check", value: "Needs Check")
        case .danger:
            return settingsLocalized("settings.icloud.status.error", value: "Error")
        }
    }

    private var manualCheckIcon: String {
        if isCheckingICloud { return "hourglass" }
        return monitor.canForceSync ? "arrow.clockwise.icloud" : "timer"
    }

    private var manualCheckTitle: String {
        if isCheckingICloud {
            return settingsLocalized("settings.icloud.checking", value: "Checking iCloud...")
        }
        guard !monitor.canForceSync else {
            return settingsLocalized("settings.icloud.check", value: "Check iCloud")
        }
        return String(
            format: settingsLocalized("cloudkit.action.check_status_wait_fmt", value: "Check again in %ds"),
            monitor.manualCheckRemainingSeconds
        )
    }

    private func formattedDate(_ date: Date?) -> String {
        date?.formatted(date: .abbreviated, time: .shortened)
            ?? settingsLocalized("common.never", value: "Never")
    }

    private func issueIconName(for severity: CloudKitMonitor.SyncHealthIssue.Severity) -> String {
        switch severity {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle.fill"
        case .danger: return "xmark.octagon.fill"
        }
    }

    private func issueTint(for severity: CloudKitMonitor.SyncHealthIssue.Severity) -> Color {
        switch severity {
        case .info: return .blue
        case .warning: return .orange
        case .danger: return .red
        }
    }
}

private struct ICloudStatusPill: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12), in: Capsule())
            .lineLimit(1)
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
                        value: "Use the iCloud section to check your last backup, account status and diagnostics. If sync stops, check that you're signed in to iCloud, that Pawtrackr is turned on under Apps Using iCloud, and that iCloud storage isn't full."
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
        VStack(alignment: .leading, spacing: 16) {
            CardView {
                SettingsCardHeader(
                    title: settingsLocalized("settings.business.identity_title", value: "Salon Identity"),
                    detail: settingsLocalized("settings.business.identity_detail", value: "This name appears on receipts, exports, and the dashboard.")
                )

                SettingsLabeledField(
                    title: settingsLocalized("settings.business.name", value: "Business Name"),
                    systemImage: "building.2.fill"
                ) {
                    TextField(settingsLocalized("settings.business.name_placeholder", value: "My Pet Grooming"), text: $appSettings.businessName)
                        .textFieldStyle(.roundedBorder)
                        .textLengthLimit($appSettings.businessName, to: TextInputLimits.name)
                }
            }

            CardView {
                SettingsCardHeader(
                    title: settingsLocalized("settings.business.receipts_title", value: "Money & Receipts"),
                    detail: settingsLocalized("settings.business.receipts_detail", value: "Keep currency short and familiar so totals stay readable in checkout and PDF receipts.")
                )

                SettingsLabeledField(
                    title: settingsLocalized("settings.business.currency_symbol", value: "Currency Symbol"),
                    systemImage: "dollarsign.circle.fill"
                ) {
                    TextField(settingsLocalized("settings.business.currency_placeholder", value: "$"), text: $appSettings.currencySymbol)
                        .textFieldStyle(.roundedBorder)
                        .textLengthLimit($appSettings.currencySymbol, to: TextInputLimits.shortText)
                }

                SettingsSmartStatusRow(
                    title: settingsLocalized("settings.business.preview_title", value: "Receipt Preview"),
                    value: businessPreview,
                    systemImage: "doc.text.magnifyingglass",
                    tint: DS.ColorToken.info
                )
            }
        }
    }

    private var businessPreview: String {
        let name = appSettings.businessName.trimmingCharacters(in: .whitespacesAndNewlines)
        let currency = appSettings.currencySymbol.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(name.isEmpty ? settingsLocalized("settings.business.unnamed", value: "Unnamed salon") : name) - \(currency.isEmpty ? "$" : currency)0.00"
    }
}

private struct PreferencesSectionView: View {
    @Bindable var appSettings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            CardView {
                SettingsCardHeader(
                    title: settingsLocalized("settings.preferences.experience_title", value: "App Experience"),
                    detail: settingsLocalized("settings.preferences.experience_detail", value: "Choose how Pawtrackr opens and which language and appearance it follows.")
                )

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
                } label: {
                    Label(settingsLocalized("settings.preferences.appearance", value: "Appearance"), systemImage: "circle.lefthalf.filled")
                }

                Picker(selection: $appSettings.defaultLaunchTab) {
                    ForEach(NavigationItem.allCases) { item in
                        Label(item.label, systemImage: item.icon)
                            .tag(item.rawValue)
                    }
                } label: {
                    Label(settingsLocalized("settings.preferences.default_launch", value: "Default Launch Tab"), systemImage: "rectangle.stack.fill")
                }

                SettingsSmartStatusRow(
                    title: settingsLocalized("settings.preferences.launch_summary", value: "Startup"),
                    value: launchSummary,
                    systemImage: "sparkle.magnifyingglass",
                    tint: DS.ColorToken.primary
                )
            }

            CardView {
                SettingsCardHeader(
                    title: settingsLocalized("settings.preferences.device_title", value: "This Workstation"),
                    detail: settingsLocalized("settings.preferences.device_detail", value: "A clear device name makes iCloud diagnostics and synced-device lists easier to trust.")
                )

                SettingsLabeledField(
                    title: settingsLocalized("settings.preferences.device_name", value: "Device Name"),
                    systemImage: "iphone.gen3"
                ) {
                    TextField(settingsLocalized("settings.preferences.device_name_placeholder", value: "Reception iPad"), text: $appSettings.deviceName)
                        .textFieldStyle(.roundedBorder)
                        .textLengthLimit($appSettings.deviceName, to: TextInputLimits.shortText)
                }

                SettingsSmartStatusRow(
                    title: settingsLocalized("settings.preferences.device_status", value: "Sync Label"),
                    value: deviceNameSummary,
                    systemImage: "checkmark.icloud.fill",
                    tint: appSettings.deviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? DS.ColorToken.warning : DS.ColorToken.success
                )
            }

            CardView {
                SettingsCardHeader(
                    title: settingsLocalized("settings.preferences.branding_title", value: "Brand & Feedback"),
                    detail: settingsLocalized("settings.preferences.branding_detail", value: "Accent color updates the app live; haptics affects taps and confirmations on supported devices.")
                )

                ColorPicker(
                    selection: brandColorBinding,
                    supportsOpacity: false
                ) {
                    Label(settingsLocalized("settings.preferences.brand_color", value: "Brand Color"), systemImage: "paintpalette.fill")
                }

                HStack {
                    Label(settingsLocalized("settings.preferences.brand_color_hex", value: "Brand Color Hex"), systemImage: "number")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(appSettings.brandColorHex.uppercased())
                        .font(.caption.monospaced())
                        .foregroundStyle(DS.ColorToken.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(DS.ColorToken.primary.opacity(0.12), in: Capsule())
                }

                Toggle(isOn: $appSettings.hapticsEnabled) {
                    Label(settingsLocalized("settings.preferences.haptics", value: "Haptic Feedback"), systemImage: "hand.tap.fill")
                }
            }

            CardView {
                SettingsCardHeader(
                    title: settingsLocalized("settings.preferences.media_title", value: "iCloud Media"),
                    detail: settingsLocalized("settings.preferences.media_detail", value: "Smart storage keeps the app lighter while still preserving synced originals when available.")
                )

                Toggle(isOn: $appSettings.optimizeMediaForICloud) {
                    Label(settingsLocalized("settings.preferences.optimize_media", value: "Optimize Media for iCloud"), systemImage: "photo.on.rectangle.angled")
                }

                SettingsSmartStatusRow(
                    title: settingsLocalized("settings.preferences.media_mode", value: "Media Mode"),
                    value: appSettings.optimizeMediaForICloud
                        ? settingsLocalized("settings.preferences.media_optimized", value: "Optimized for iCloud sync")
                        : settingsLocalized("settings.preferences.media_originals", value: "Keep originals on this device"),
                    systemImage: appSettings.optimizeMediaForICloud ? "icloud.and.arrow.up.fill" : "externaldrive.fill",
                    tint: appSettings.optimizeMediaForICloud ? DS.ColorToken.success : DS.ColorToken.info
                )
            }
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

    private var launchSummary: String {
        let selected = NavigationItem(rawValue: appSettings.defaultLaunchTab) ?? .dashboard
        return String(
            format: settingsLocalized("settings.preferences.launch_summary_fmt", value: "Opens to %@"),
            selected.label
        )
    }

    private var deviceNameSummary: String {
        let trimmed = appSettings.deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return settingsLocalized("settings.preferences.device_name_missing", value: "Add a name so synced devices are easy to identify.")
        }

        return String(
            format: settingsLocalized("settings.preferences.device_name_sync_fmt", value: "%@ will appear in iCloud diagnostics."),
            trimmed
        )
    }
}

private struct SecuritySectionView: View {
    @Bindable var appSettings: AppSettings
    @Binding var showChangePIN: Bool
    @State private var showDisableLockConfirm = false
    /// True while we're routing the user to set a PIN before enabling the lock.
    @State private var pendingEnableLock = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            CardView {
                SettingsCardHeader(
                    title: settingsLocalized("settings.security.protection_title", value: "Access Protection"),
                    detail: securitySummary
                )

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

                SettingsSmartStatusRow(
                    title: settingsLocalized("settings.security.pin_status", value: "PIN Status"),
                    value: pinStatus,
                    systemImage: appSettings.isLockEnabled ? "checkmark.shield.fill" : "shield.slash.fill",
                    tint: appSettings.isLockEnabled ? DS.ColorToken.success : DS.ColorToken.warning
                )

                if appSettings.isLockEnabled {
                    Button(settingsLocalized("settings.pin.change", value: "Change PIN")) { showChangePIN = true }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("settings.changePIN")
                }
            }

            CardView {
                SettingsCardHeader(
                    title: settingsLocalized("settings.security.auto_lock_title", value: "Auto-Lock Rules"),
                    detail: settingsLocalized("settings.security.auto_lock_detail", value: "Use these controls for shared front-desk devices or grooming-room stations.")
                )

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

                SettingsSmartStatusRow(
                    title: settingsLocalized("settings.security.lock_timing", value: "Lock Timing"),
                    value: autoLockSummary,
                    systemImage: "timer.circle.fill",
                    tint: appSettings.autoLockAfterInactivity ? DS.ColorToken.success : DS.ColorToken.info
                )
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

    private var securitySummary: String {
        appSettings.isLockEnabled
            ? settingsLocalized("settings.security.enabled_detail", value: "Client records are protected when Pawtrackr opens or returns to the foreground.")
            : settingsLocalized("settings.security.disabled_detail", value: "App lock is off. Turn it on before sharing this device with staff.")
    }

    private var pinStatus: String {
        if appSettings.isLockEnabled {
            return appSettings.isBiometricLockEnabled
                ? settingsLocalized("settings.security.pin_biometric", value: "PIN set with biometric unlock enabled")
                : settingsLocalized("settings.security.pin_only", value: "PIN set")
        }

        return settingsLocalized("settings.security.pin_disabled", value: "Not required")
    }

    private var autoLockSummary: String {
        guard appSettings.isLockEnabled else {
            return settingsLocalized("settings.security.auto_lock_disabled", value: "Enable app lock to use automatic locking.")
        }

        if appSettings.autoLockAfterInactivity {
            return String(
                format: settingsLocalized("settings.security.lock_after_inactivity_detail_fmt", value: "Locks after %d minutes without interaction."),
                appSettings.idleLockMinutes
            )
        }

        if appSettings.autoLockOnBackground {
            return settingsLocalized("settings.security.lock_on_close_only", value: "Locks when the app closes or moves to the background.")
        }

        return settingsLocalized("settings.security.manual_lock_only", value: "Manual lock only.")
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

private struct SettingsCardHeader: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsSmartStatusRow: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 22)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(value)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
    let dataLossSuspected: Bool

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
                .accessibilityIdentifier("settings.replayGettingStarted")
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .walkthroughTarget(.setAbout)

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

                if dataLossSuspected {
                    Label(
                        settingsLocalized(
                            "data_safety.start_fresh_locked",
                            value: "Locked while Pawtrackr checks missing client data."
                        ),
                        systemImage: "lock.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DS.ColorToken.danger)
                }

                Button(role: .destructive) {
                    showWipeConfirm = true
                } label: {
                    Label(settingsLocalized("settings.wipe.button", value: "Wipe & Start Fresh"), systemImage: "exclamationmark.triangle.fill")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(dataLossSuspected)
                .walkthroughTarget(.setStartFresh)
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
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.accentColor.opacity(isHovering ? 0.18 : 0), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
            .onHover { isHovering = $0 }
            .animation(.easeInOut(duration: 0.15), value: isHovering)
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

    @ViewBuilder
    func optionalWalkthroughTarget(_ id: WalkthroughAnchorID?) -> some View {
        if let id {
            walkthroughTarget(id)
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
