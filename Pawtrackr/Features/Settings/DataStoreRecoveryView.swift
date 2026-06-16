//
//  DataStoreRecoveryView.swift
//  Pawtrackr
//
//  Shown when the SwiftData container fails to initialize at launch.
//  Most common cause: schema changed since the previous run and the
//  on-disk store can't be migrated. Offers the user a one-tap "Reset
//  Local Data" button that backs up the store files to a timestamped
//  folder before clearing them, then asks the user to relaunch.
//
//  The backup means we never destroy the user's data without a way to
//  recover it manually if needed.
//

import SwiftUI
import OSLog
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct DataStoreRecoveryView: View {
    @State private var hasReset = false
    @State private var resetDetail: String?
    @State private var resetError: String?

    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "Recovery")

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .font(.system(size: 56))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.orange)
                    .padding(.top, 40)

                Text(AppLocalization.localized("recovery.title", value: "Couldn't open your data"))
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)

                Text(AppLocalization.localized(
                    "recovery.body",
                    value: "Pawtrackr's local data store can't be opened. This usually happens after an app update changed the database. Your iCloud data is safe and will re-download once we reset the local copy."
                ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

                if let detail = lastErrorDetail {
                    DisclosureGroup(AppLocalization.localized("recovery.show_details", value: "Show technical details")) {
                        Text(detail)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.secondary.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .padding(.horizontal, 24)
                }

                if hasReset {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.green)
                        Text(AppLocalization.localized("recovery.reset_done.title", value: "Reset complete"))
                            .font(.headline)
                        Text(AppLocalization.localized(
                            "recovery.reset_done.body",
                            value: "Quit and reopen Pawtrackr. Your data will sync back from iCloud if you have iCloud sync enabled."
                        ))
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        if let detail = resetDetail {
                            Text(detail)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.top, 12)
                } else {
                    VStack(spacing: 12) {
                        Button {
                            repairStore()
                        } label: {
                            Label(AppLocalization.localized("recovery.repair_button", value: "Repair Storage (Safe)"),
                                  systemImage: "wrench.adjustable")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            resetStore()
                        } label: {
                            Label(AppLocalization.localized("recovery.reset_button", value: "Reset Local Data"),
                                  systemImage: "arrow.counterclockwise")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)

                        if let err = resetError {
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                }

                Spacer(minLength: 40)
            }
        }
    }

    private var lastErrorDetail: String? {
        UserDefaults.standard.string(forKey: PawtrackrApp.lastInitErrorKey)
    }

    private func repairStore() {
        StoreHealthCheck.clearAuxiliaryCaches()
        resetDetail = AppLocalization.localized("recovery.repair_done", value: "Repair complete. Please try relaunching the app.")
        hasReset = true
    }

    private func resetStore() {
        do {
            let archive = try Self.archiveExistingStore()
            hasReset = true
            resetError = nil
            resetDetail = archive.movedFiles.isEmpty
                ? AppLocalization.localized("recovery.no_files_found", value: "No store files were present.")
                : String.localizedStringWithFormat(
                    AppLocalization.localized("recovery.archived_n", value: "Archived %d file(s)"),
                    archive.movedFiles.count
                ) + "\n" + archive.backupDirectory.path
            UserDefaults.standard.removeObject(forKey: PawtrackrApp.lastInitErrorKey)
            CloudKitMonitor.resetPersistedSyncStateForLocalStoreReset()
            CloudKitMonitor.recordLocalStoreResetArchivedFiles(archive.movedFiles.count)
            log.info("Store reset complete; archived \(archive.movedFiles.count) files.")
        } catch {
            resetError = String(format: AppLocalization.localized("recovery.reset_failed", value: "Couldn't reset: %@"), error.localizedDescription)
            log.error("Store reset failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Moves SwiftData store files (.store, .store-shm, .store-wal) into a
    /// timestamped backup folder. Returns the list of file URLs moved.
    /// Crucially, this does NOT delete the data — the backup folder remains.
    private static func archiveExistingStore() throws -> StoreArchive {
        let fm = FileManager.default
        let appSupport = try fm.url(for: .applicationSupportDirectory,
                                    in: .userDomainMask,
                                    appropriateFor: nil,
                                    create: true)

        // SwiftData places store files at the configured name. Our config
        // name is "Pawtrackr", so look for "Pawtrackr.store*" plus the
        // legacy "default.store*" used by some Xcode templates.
        let candidates = ["Pawtrackr.store", "default.store"]
        let allContents = (try? fm.contentsOfDirectory(at: appSupport, includingPropertiesForKeys: nil)) ?? []

        let targets: [URL] = allContents.filter { url in
            let name = url.lastPathComponent
            return candidates.contains(where: { base in
                name == base || name.hasPrefix(base + "-") || name.hasPrefix(base + "_")
            })
        }

        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backupDir = appSupport.appendingPathComponent("RecoveryBackup-\(stamp)", isDirectory: true)
        try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)

        var moved: [URL] = []
        for url in targets {
            let dest = backupDir.appendingPathComponent(url.lastPathComponent)
            try fm.moveItem(at: url, to: dest)
            moved.append(dest)
        }

        let manifest = [
            "Pawtrackr local store recovery archive",
            "Created: \(Date().formatted(date: .complete, time: .standard))",
            "Last init error: \(UserDefaults.standard.string(forKey: PawtrackrApp.lastInitErrorKey) ?? "none")",
            "Archived files:",
            moved.isEmpty ? "- none" : moved.map { "- \($0.lastPathComponent)" }.joined(separator: "\n")
        ].joined(separator: "\n")
        try manifest.write(
            to: backupDir.appendingPathComponent("README.txt"),
            atomically: true,
            encoding: .utf8
        )

        return StoreArchive(backupDirectory: backupDir, movedFiles: moved)
    }

    private struct StoreArchive {
        let backupDirectory: URL
        let movedFiles: [URL]
    }
}
