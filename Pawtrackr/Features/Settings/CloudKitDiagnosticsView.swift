//
//  CloudKitDiagnosticsView.swift
//  Pawtrackr
//
//  Hidden diagnostics screen revealed by tapping Settings → Version 7 times.
//  Displays raw iCloud state so we can debug a customer issue remotely.
//
//  All values can be safely shown to the user — they're already visible to them
//  in their Apple ID settings or in Console.app.
//

import SwiftUI
import CloudKit
import SwiftData

struct CloudKitDiagnosticsView: View {
    @Environment(DataStoreService.self) private var dataStore
    @Query(sort: \DeviceMetadata.lastSyncAt, order: .reverse) private var devices: [DeviceMetadata]
    @State private var monitor = CloudKitMonitor.shared
    @State private var copySuccessTimestamp: Date?
    @State private var isRebuildingInsights = false
    @State private var rebuildMessage: String?
    @State private var lastSummaryRebuildDate = UserDefaults.standard.object(forKey: "lastSummaryRebuildDate") as? Date

    var body: some View {
        Form {
            Section(NSLocalizedString("cloudkit.diagnostics.account", value: "Account", comment: "")) {
                row(NSLocalizedString("cloudkit.diagnostics.account_status", value: "Account Status", comment: ""),
                    monitor.accountState.displayLabel)
                row(NSLocalizedString("cloudkit.diagnostics.container", value: "Container ID", comment: ""),
                    monitor.containerIdentifier, monospaced: true)
                row(NSLocalizedString("cloudkit.diagnostics.network", value: "Network", comment: ""),
                    monitor.networkState.displayLabel)
            }

            Section("Connected Devices") {
                if devices.isEmpty {
                    Text("No other devices found yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(devices) { device in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(device.name)
                                    .font(.subheadline.weight(.semibold))
                                if device.deviceID == DeviceIdentity.currentID {
                                    Text("(This Device)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(device.lastSyncAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text("\(device.model) • \(device.osVersion)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section(NSLocalizedString("cloudkit.diagnostics.health", value: "Health", comment: "")) {
                row(NSLocalizedString("cloudkit.diagnostics.health_headline", value: "Summary", comment: ""),
                    monitor.healthHeadline)
                row(NSLocalizedString("cloudkit.diagnostics.health_detail", value: "Detail", comment: ""),
                    monitor.healthDetail)
                if monitor.healthIssues.isEmpty {
                    Label(NSLocalizedString("cloudkit.health.ok", value: "iCloud sync looks healthy", comment: ""),
                          systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                } else {
                    ForEach(monitor.healthIssues) { issue in
                        VStack(alignment: .leading, spacing: 3) {
                            Label(issue.title, systemImage: iconName(for: issue.severity))
                                .foregroundStyle(tint(for: issue.severity))
                            Text(issue.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section(NSLocalizedString("cloudkit.diagnostics.sync", value: "Sync", comment: "")) {
                row(NSLocalizedString("cloudkit.diagnostics.state", value: "Current State", comment: ""), syncStateText)
                row(NSLocalizedString("cloudkit.diagnostics.last_sync", value: "Last Sync", comment: ""),
                    monitor.lastSyncDate.map { $0.formatted(date: .abbreviated, time: .standard) } ?? "—")
                row(NSLocalizedString("cloudkit.diagnostics.last_attempt", value: "Last Check", comment: ""),
                    monitor.lastAttemptDate.map { $0.formatted(date: .abbreviated, time: .standard) } ?? "—")
                row(NSLocalizedString("cloudkit.diagnostics.last_import", value: "Last Import", comment: ""),
                    monitor.lastImportDate.map { $0.formatted(date: .abbreviated, time: .standard) } ?? "—")
                row(NSLocalizedString("cloudkit.diagnostics.last_export", value: "Last Export", comment: ""),
                    monitor.lastExportDate.map { $0.formatted(date: .abbreviated, time: .standard) } ?? "—")
                row(NSLocalizedString("cloudkit.diagnostics.first_sync", value: "First Sync Done", comment: ""),
                    monitor.firstSyncCompleted ? "Yes" : "No")
                row(NSLocalizedString("cloudkit.diagnostics.quota_exceeded", value: "Quota Exceeded", comment: ""),
                    monitor.quotaExceeded ? "Yes" : "No")
                row(NSLocalizedString("cloudkit.diagnostics.app_access", value: "App Access Warning", comment: ""),
                    monitor.iCloudAppAccessMayBeDisabled ? "Yes" : "No")
                row(NSLocalizedString("cloudkit.diagnostics.pending", value: "Pending Local Changes", comment: ""),
                    monitor.pendingChangesSummary ?? "No")
                row("Last Insights Rebuild",
                    lastSummaryRebuildDate.map { $0.formatted(date: .abbreviated, time: .standard) } ?? "—")
                if let err = monitor.lastErrorMessage {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("cloudkit.diagnostics.last_error", value: "Last Error", comment: ""))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(err)
                            .font(.caption.monospaced())
                    }
                }
            }

            Section(NSLocalizedString("cloudkit.diagnostics.events", value: "Recent Sync Events", comment: "")) {
                if monitor.syncEvents.isEmpty {
                    Text(NSLocalizedString("cloudkit.diagnostics.no_events", value: "No sync events recorded yet.", comment: ""))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(monitor.syncEvents) { event in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Label(event.kind.displayLabel, systemImage: eventIconName(for: event))
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                Text(event.status.displayLabel)
                                    .font(.caption)
                                    .foregroundStyle(eventTint(for: event))
                            }
                            Text(event.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack {
                                Text(event.startedAt.formatted(date: .abbreviated, time: .standard))
                                if let duration = event.durationSeconds {
                                    Text(String(format: "%.1fs", duration))
                                }
                                if let errorCode = event.errorCode {
                                    Text(errorCode)
                                        .font(.caption2.monospaced())
                                }
                            }
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            Section {
                Button {
                    Task { await monitor.forceSync() }
                } label: {
                    Label(manualCheckTitle,
                          systemImage: monitor.canForceSync ? "arrow.clockwise.icloud" : "timer")
                }
                .disabled(!monitor.canForceSync)

                Button {
                    Task { await monitor.refreshAccountStatus() }
                } label: {
                    Label(NSLocalizedString("cloudkit.diagnostics.recheck_account", value: "Re-check Account", comment: ""),
                          systemImage: "person.crop.circle.badge.questionmark")
                }

                Button {
                    Task { await rebuildInsightsCache() }
                } label: {
                    Label("Rebuild Insights Cache", systemImage: "chart.bar.doc.horizontal")
                }
                .disabled(isRebuildingInsights)

                if isRebuildingInsights {
                    ProgressView("Rebuilding insights…")
                }

                if let rebuildMessage {
                    Text(rebuildMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    copyDiagnostics()
                } label: {
                    Label(copyLabel, systemImage: "doc.on.doc")
                }
            }
        }
        .navigationTitle(NSLocalizedString("cloudkit.diagnostics.title", value: "iCloud Diagnostics", comment: ""))
    }

    @ViewBuilder
    private func row(_ key: String, _ value: String, monospaced: Bool = false) -> some View {
        HStack {
            Text(key).foregroundStyle(.secondary)
            Spacer()
            Group {
                if monospaced {
                    Text(value).font(.caption.monospaced())
                } else {
                    Text(value)
                }
            }
            .multilineTextAlignment(.trailing)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
        }
    }

    private var syncStateText: String {
        switch monitor.syncState {
        case .idle: return "Idle"
        case .syncing: return "Syncing"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    private var copyLabel: String {
        if let ts = copySuccessTimestamp, Date().timeIntervalSince(ts) < 2 {
            return NSLocalizedString("common.copied", value: "Copied!", comment: "")
        }
        return NSLocalizedString("cloudkit.diagnostics.copy", value: "Copy Diagnostics", comment: "")
    }

    private func copyDiagnostics() {
        let lines: [String] = [
            "Pawtrackr iCloud Diagnostics",
            "Container: \(monitor.containerIdentifier)",
            "Account: \(monitor.accountState.displayLabel)",
            "Network: \(monitor.networkState.displayLabel)",
            "State: \(syncStateText)",
            "Health: \(monitor.healthHeadline)",
            "Health detail: \(monitor.healthDetail)",
            "Last sync: \(monitor.lastSyncDate.map { $0.formatted(date: .abbreviated, time: .standard) } ?? "never")",
            "Last check: \(monitor.lastAttemptDate.map { $0.formatted(date: .abbreviated, time: .standard) } ?? "never")",
            "Last import: \(monitor.lastImportDate.map { $0.formatted(date: .abbreviated, time: .standard) } ?? "never")",
            "Last export: \(monitor.lastExportDate.map { $0.formatted(date: .abbreviated, time: .standard) } ?? "never")",
            "Last insights rebuild: \(lastSummaryRebuildDate.map { $0.formatted(date: .abbreviated, time: .standard) } ?? "never")",
            "First sync done: \(monitor.firstSyncCompleted)",
            "Pending changes: \(monitor.pendingChangesSummary ?? "none")",
            "Quota exceeded: \(monitor.quotaExceeded)",
            "App access warning: \(monitor.iCloudAppAccessMayBeDisabled)",
            "Last error: \(monitor.lastErrorMessage ?? "none")",
            "",
            "Health issues:",
            monitor.healthIssues.isEmpty ? "- none" : monitor.healthIssues.map { "- \($0.title): \($0.detail)" }.joined(separator: "\n"),
            "",
            "Recent events:",
            monitor.syncEvents.isEmpty ? "- none" : monitor.syncEvents.map { event in
                let date = event.startedAt.formatted(date: .abbreviated, time: .standard)
                let code = event.errorCode.map { " [\($0)]" } ?? ""
                return "- \(date) \(event.kind.displayLabel) \(event.status.displayLabel): \(event.message)\(code)"
            }.joined(separator: "\n")
        ]
        let text = lines.joined(separator: "\n")
        #if canImport(UIKit) && !targetEnvironment(macCatalyst)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
        copySuccessTimestamp = Date()
    }

    private func rebuildInsightsCache() async {
        guard !isRebuildingInsights else { return }
        isRebuildingInsights = true
        rebuildMessage = nil

        let container = dataStore.container
        await Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            SummaryUpdater.rebuildAllSummaries(in: context)
        }.value

        lastSummaryRebuildDate = UserDefaults.standard.object(forKey: "lastSummaryRebuildDate") as? Date
        rebuildMessage = lastSummaryRebuildDate.map {
            "Insights cache rebuilt at \($0.formatted(date: .omitted, time: .standard))."
        } ?? "Insights cache rebuild finished."
        isRebuildingInsights = false
    }

    private func iconName(for severity: CloudKitMonitor.SyncHealthIssue.Severity) -> String {
        switch severity {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle.fill"
        case .danger: return "xmark.octagon.fill"
        }
    }

    private func tint(for severity: CloudKitMonitor.SyncHealthIssue.Severity) -> Color {
        switch severity {
        case .info: return .blue
        case .warning: return .orange
        case .danger: return .red
        }
    }

    private func eventIconName(for event: CloudKitMonitor.SyncEvent) -> String {
        switch event.kind {
        case .setup: return "gearshape.2"
        case .importFromCloud: return "icloud.and.arrow.down"
        case .exportToCloud: return "icloud.and.arrow.up"
        case .account: return "person.crop.circle"
        case .localChange: return "pencil.and.list.clipboard"
        case .remotePush: return "bell.badge"
        case .recovery: return "externaldrive.badge.checkmark"
        case .media: return "photo"
        case .healthCheck: return "stethoscope"
        }
    }

    private func eventTint(for event: CloudKitMonitor.SyncEvent) -> Color {
        switch event.status {
        case .failed: return .red
        case .waiting: return .orange
        case .succeeded: return .green
        case .started, .noted: return .secondary
        }
    }

    private var manualCheckTitle: String {
        guard !monitor.canForceSync else {
            return NSLocalizedString("cloudkit.action.check_status", value: "Check iCloud", comment: "")
        }
        return String(
            format: NSLocalizedString(
                "cloudkit.action.check_status_wait_fmt",
                value: "Check again in %ds",
                comment: ""
            ),
            monitor.manualCheckRemainingSeconds
        )
    }
}

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
