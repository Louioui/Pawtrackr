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

struct CloudKitDiagnosticsView: View {
    @State private var monitor = CloudKitMonitor.shared
    @State private var copySuccessTimestamp: Date?

    var body: some View {
        Form {
            Section(NSLocalizedString("cloudkit.diagnostics.account", value: "Account", comment: "")) {
                row(NSLocalizedString("cloudkit.diagnostics.account_status", value: "Account Status", comment: ""),
                    monitor.accountState.displayLabel)
                row(NSLocalizedString("cloudkit.diagnostics.container", value: "Container ID", comment: ""),
                    monitor.containerIdentifier, monospaced: true)
            }

            Section(NSLocalizedString("cloudkit.diagnostics.sync", value: "Sync", comment: "")) {
                row(NSLocalizedString("cloudkit.diagnostics.state", value: "Current State", comment: ""), syncStateText)
                row(NSLocalizedString("cloudkit.diagnostics.last_sync", value: "Last Sync", comment: ""),
                    monitor.lastSyncDate.map { $0.formatted(date: .abbreviated, time: .standard) } ?? "—")
                row(NSLocalizedString("cloudkit.diagnostics.first_sync", value: "First Sync Done", comment: ""),
                    monitor.firstSyncCompleted ? "Yes" : "No")
                row(NSLocalizedString("cloudkit.diagnostics.quota_exceeded", value: "Quota Exceeded", comment: ""),
                    monitor.quotaExceeded ? "Yes" : "No")
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

            Section {
                Button {
                    Task { await monitor.forceSync() }
                } label: {
                    Label(NSLocalizedString("cloudkit.action.sync_now", value: "Sync Now", comment: ""),
                          systemImage: "arrow.clockwise.icloud")
                }

                Button {
                    Task { await monitor.refreshAccountStatus() }
                } label: {
                    Label(NSLocalizedString("cloudkit.diagnostics.recheck_account", value: "Re-check Account", comment: ""),
                          systemImage: "person.crop.circle.badge.questionmark")
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
            "State: \(syncStateText)",
            "Last sync: \(monitor.lastSyncDate.map { $0.formatted(date: .abbreviated, time: .standard) } ?? "never")",
            "First sync done: \(monitor.firstSyncCompleted)",
            "Quota exceeded: \(monitor.quotaExceeded)",
            "Last error: \(monitor.lastErrorMessage ?? "none")"
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
}

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
