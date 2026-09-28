//
//  DataStoreRecoveryView.swift
//  Pawtrackr
//
//  Shown when the SwiftData container fails to initialize at launch.
//
//  The store on disk is almost always intact when this appears: in the 1.0.2
//  incident it was a migration failure (NSCocoaErrorDomain 134504) that a code
//  fix resolved. This screen therefore steers users away from anything
//  destructive. Its old copy promised "Your iCloud data is safe and will
//  re-download once we reset the local copy" next to a prominent Reset button;
//  users who tapped it saw every client disappear, because nothing had ever
//  reached iCloud. Reset now sits under Advanced, behind a confirmation that
//  says how many clients it moves aside, and it still only archives files.
//
//  The screen also shows the one iCloud fact that survives without a
//  container: when this device last had an upload confirmed. With none, a
//  failing streak or only an old one, it warns that a reset leaves the app
//  empty. It warns and doesn't block; export needs the store this screen
//  can't open.
//

import SwiftUI
import OSLog

struct DataStoreRecoveryView: View {
    @State private var clientsOnDevice: Int?
    /// This device's upload record and the report lines built from it. Read
    /// from UserDefaults once: no container exists here, and decoding it on
    /// every render is waste.
    @State private var uploadRecord: SyncHealthReducer.State?
    @State private var evidenceLines: [String] = []
    @State private var showResetConfirmation = false
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
                    "recovery.body_safe",
                    value: "Your data is still saved on this device — Pawtrackr just couldn't open it. Please don't delete the app. Send the details below to support so we can get you back in."
                ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

                if let clientsOnDevice, clientsOnDevice > 0 {
                    Label(
                        String(
                            format: AppLocalization.localized("recovery.clients_on_device_fmt", value: "%d clients are saved on this device."),
                            clientsOnDevice
                        ),
                        systemImage: "checkmark.shield.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
                    .accessibilityIdentifier("recovery.clientsOnDevice")
                }

                // Gone after a reset: its warning is about the step just taken.
                if let uploadRecord, !hasReset {
                    uploadEvidence(for: uploadRecord)
                }

                if let detail = lastErrorDetail {
                    DisclosureGroup(AppLocalization.localized("recovery.show_details", value: "Show technical details")) {
                        Text(detail)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
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
                            "recovery.reset_done.body_backup",
                            value: "Close and reopen Pawtrackr. Your previous data is kept in a backup on this device, and Pawtrackr will offer to bring it back once a fixed version can open it."
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
                    .padding(.horizontal, 24)
                } else {
                    VStack(spacing: 16) {
                        ShareLink(item: supportReport) {
                            Label(
                                AppLocalization.localized("recovery.share_details", value: "Send Details to Support"),
                                systemImage: "square.and.arrow.up"
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("recovery.shareDetails")

                        DisclosureGroup(AppLocalization.localized("recovery.advanced", value: "Advanced")) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(AppLocalization.localized(
                                    "recovery.reset_warning",
                                    value: "Only reset if Pawtrackr support asks you to. It starts an empty database; your current data is moved to a backup on this device."
                                ))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                                Button(role: .destructive) {
                                    showResetConfirmation = true
                                } label: {
                                    Label(AppLocalization.localized("recovery.reset_button", value: "Reset Local Data"),
                                          systemImage: "arrow.counterclockwise")
                                }
                                .buttonStyle(.bordered)
                                .accessibilityIdentifier("recovery.reset")
                            }
                            .padding(.top, 8)
                        }

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
        .confirmationDialog(
            AppLocalization.localized("recovery.reset_confirm.title", value: "Reset local data?"),
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button(AppLocalization.localized("recovery.reset_button", value: "Reset Local Data"), role: .destructive) {
                resetStore()
            }
            Button(AppLocalization.localized("common.cancel", value: "Cancel"), role: .cancel) {}
        } message: {
            Text(resetConfirmationMessage)
        }
        .task {
            uploadRecord = CloudKitMonitor.persistedOrMigratedSyncHealth()
            evidenceLines = CloudKitMonitor.persistedUploadEvidenceLines() + CloudKitMonitor.recentSyncEventLines()
            clientsOnDevice = await Task.detached(priority: .userInitiated) {
                Self.clientRowCountInLiveStore()
            }.value
        }
    }

    private var lastErrorDetail: String? {
        UserDefaults.standard.string(forKey: PawtrackrApp.lastInitErrorKey)
    }

    private func uploadEvidence(for record: SyncHealthReducer.State) -> some View {
        VStack(spacing: 6) {
            Label(Self.lastUploadText(for: record), systemImage: "icloud")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if SyncStatusPolicy.lacksRecentUpload(record, now: Date()) {
                Text(Self.noRecentCopyWarning)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("recovery.lastUpload")
    }

    /// "From this device" on purpose: an upload only proves some export
    /// succeeded here, not that every client reached iCloud.
    private static func lastUploadText(for record: SyncHealthReducer.State) -> String {
        guard let uploadedAt = record.lastSuccessfulExportEndedAt else {
            return AppLocalization.localized(
                "recovery.last_upload_never",
                value: "Last confirmed iCloud upload from this device: Never"
            )
        }
        return String(
            format: AppLocalization.localized(
                "recovery.last_upload_fmt",
                value: "Last confirmed iCloud upload from this device: %@"
            ),
            uploadedAt.formatted(date: .abbreviated, time: .shortened)
        )
    }

    private static var noRecentCopyWarning: String {
        AppLocalization.localized(
            "recovery.no_recent_icloud_copy",
            value: "iCloud does not have a recent copy from this device. Resetting will leave Pawtrackr empty here."
        )
    }

    private var resetConfirmationMessage: String {
        var message: String
        if let clientsOnDevice, clientsOnDevice > 0 {
            message = String(
                format: AppLocalization.localized(
                    "recovery.reset_confirm.message_fmt",
                    value: "The %d clients saved on this device will be moved into a backup folder and Pawtrackr will start empty. They only come back on their own if iCloud sync had already uploaded them."
                ),
                clientsOnDevice
            )
        } else {
            message = AppLocalization.localized(
                "recovery.reset_confirm.message",
                value: "Your data will be moved into a backup folder on this device and Pawtrackr will start empty."
            )
        }
        // The evidence goes where the decision is made, not only on the screen
        // behind the dialog.
        if let uploadRecord {
            message += "\n\n" + Self.lastUploadText(for: uploadRecord)
            if SyncStatusPolicy.lacksRecentUpload(uploadRecord, now: Date()) {
                message += "\n\n" + Self.noRecentCopyWarning
            }
        }
        return message
    }

    private var supportReport: String {
        let info = Bundle.main.infoDictionary
        let summary = [
            "Pawtrackr couldn't open its data store.",
            "App: \(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))",
            "Clients on device: \(clientsOnDevice.map(String.init) ?? "unknown")",
            "Error: \(lastErrorDetail ?? "none recorded")"
        ]
        // Read from UserDefaults, which works without a container: whether
        // anything from this device ever reached iCloud decides what a reset
        // would cost.
        return (summary + evidenceLines).joined(separator: "\n")
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
                ) + "\n" + archive.backupDirectory.lastPathComponent
            UserDefaults.standard.removeObject(forKey: PawtrackrApp.lastInitErrorKey)
            CloudKitMonitor.resetPersistedSyncStateForLocalStoreReset()
            CloudKitMonitor.recordLocalStoreResetArchivedFiles(archive.movedFiles.count)
            log.info("Store reset complete; archived \(archive.movedFiles.count) files.")
        } catch {
            resetError = String(format: AppLocalization.localized("recovery.reset_failed", value: "Couldn't reset: %@"), error.localizedDescription)
            log.error("Store reset failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// File-system only, so it runs off the main actor.
    nonisolated private static func clientRowCountInLiveStore() -> Int? {
        guard let appSupport = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else {
            return nil
        }
        return StoreFileMigration.clientRowCount(in: appSupport.appendingPathComponent("Pawtrackr.store"))
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
        // The build goes in the name: this build couldn't open the store, so
        // StoreBackupRestore won't offer it back until a different build ships.
        let build = StoreFileMigration.appBuildIdentifier.replacingOccurrences(of: "/", with: "-")
        let backupDir = appSupport.appendingPathComponent("RecoveryBackup-\(build)-\(stamp)", isDirectory: true)
        try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)

        var moved: [URL] = []
        for url in targets {
            let dest = backupDir.appendingPathComponent(url.lastPathComponent)
            try fm.moveItem(at: url, to: dest)
            moved.append(dest)
        }

        // Written before resetStore clears the sync keys, so it still has the
        // evidence. A later reset or restore overwrites the preReset copy in
        // UserDefaults; this file keeps the one for this archive.
        let manifest = ([
            "Pawtrackr local store recovery archive",
            "Created: \(Date().formatted(date: .complete, time: .standard))",
            "Last init error: \(UserDefaults.standard.string(forKey: PawtrackrApp.lastInitErrorKey) ?? "none")",
            "Archived files:",
            moved.isEmpty ? "- none" : moved.map { "- \($0.lastPathComponent)" }.joined(separator: "\n"),
            "",
            "iCloud evidence for this store at the time of the reset:"
        ] + CloudKitMonitor.persistedUploadEvidenceLines() + CloudKitMonitor.recentSyncEventLines()).joined(separator: "\n")
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
