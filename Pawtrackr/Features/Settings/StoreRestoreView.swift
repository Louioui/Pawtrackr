//
//  StoreRestoreView.swift
//  Pawtrackr
//
//  Lists the on-device store backups and schedules one to be restored on the
//  next launch. Takes the live client count as a parameter rather than reading
//  the model context, because it's presented as a sheet and environment values
//  don't reliably reach sheet content on every platform.
//

import SwiftUI

struct StoreRestoreView: View {
    let currentClientCount: Int

    @Environment(\.dismiss) private var dismiss
    @State private var candidates: [StoreBackupRestore.Candidate] = []
    @State private var isLoading = true
    @State private var pendingConfirmation: StoreBackupRestore.Candidate?
    @State private var scheduledDirectory = StoreBackupRestore.scheduledRestoreDirectory()

    var body: some View {
        NavigationStack {
            List {
                if let scheduledDirectory {
                    Section {
                        scheduledNotice(for: scheduledDirectory)
                    }
                }

                Section {
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else if restorable.isEmpty {
                        Text(localized("store_restore.none", value: "No backups with clients were found on this device."))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(restorable) { candidate in
                            Button {
                                pendingConfirmation = candidate
                            } label: {
                                row(for: candidate)
                            }
                            .disabled(scheduledDirectory != nil)
                            .accessibilityIdentifier("storeRestore.candidate.\(candidate.kind.rawValue)")
                        }
                    }
                } header: {
                    Text(String(
                        format: localized("store_restore.current_fmt", value: "Clients on this device now: %d"),
                        currentClientCount
                    ))
                } footer: {
                    Text(localized(
                        "store_restore.footer",
                        value: "Restoring replaces the clients Pawtrackr shows now with the ones in the backup. What's here now is moved into its own backup on this device, not deleted."
                    ))
                }
            }
            .navigationTitle(localized("store_restore.title", value: "Restore Clients"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(localized("common.done", value: "Done")) { dismiss() }
                }
            }
            .confirmationDialog(
                localized("store_restore.confirm.title", value: "Restore this backup?"),
                isPresented: Binding(
                    get: { pendingConfirmation != nil },
                    set: { if !$0 { pendingConfirmation = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingConfirmation
            ) { candidate in
                Button(String(
                    format: localized("store_restore.confirm.action_fmt", value: "Restore %d Clients"),
                    candidate.clientCount
                )) {
                    StoreBackupRestore.scheduleRestore(of: candidate)
                    scheduledDirectory = candidate.directoryName
                }
                Button(localized("common.cancel", value: "Cancel"), role: .cancel) {}
            } message: { candidate in
                Text(confirmationMessage(for: candidate))
            }
            .task { await loadCandidates() }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 420)
        #endif
    }

    private func confirmationMessage(for candidate: StoreBackupRestore.Candidate) -> String {
        let backupDate = candidate.createdAt.formatted(date: .abbreviated, time: .shortened)
        var message = currentClientCount == 0
            ? String(
                format: localized(
                    "store_restore.confirm.message_empty_fmt",
                    value: "Pawtrackr brings back the %1$d clients from %2$@ the next time it opens."
                ),
                candidate.clientCount,
                backupDate
            )
            : String(
                format: localized(
                    "store_restore.confirm.message_fmt",
                    value: "The %1$d clients on this device now will be kept in a separate backup. Pawtrackr brings back the %2$d clients from %3$@ the next time it opens."
                ),
                currentClientCount,
                candidate.clientCount,
                backupDate
            )
        // With iCloud on, the restored store also downloads whatever this
        // device already synced, so the result is both sets, not a swap.
        if CloudKitMonitor.shared.accountState.isAvailable {
            message += "\n\n" + localized(
                "store_restore.confirm.icloud_note",
                value: "iCloud sync is on, so clients already saved in iCloud will also come back alongside the restored ones."
            )
        }
        return message
    }

    private var restorable: [StoreBackupRestore.Candidate] {
        candidates.filter { $0.clientCount > 0 }
    }

    private func row(for candidate: StoreBackupRestore.Candidate) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon(for: candidate.kind))
                .foregroundStyle(DS.ColorToken.primary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title(for: candidate.kind))
                    .foregroundStyle(.primary)
                Text(candidate.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(String(
                format: localized("store_restore.client_count_fmt", value: "%d clients"),
                candidate.clientCount
            ))
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
        }
        .contentShape(Rectangle())
    }

    private func scheduledNotice(for directoryName: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                localized("store_restore.scheduled.title", value: "Restore ready"),
                systemImage: "checkmark.circle.fill"
            )
            .font(.headline)
            .foregroundStyle(DS.ColorToken.success)

            Text(relaunchInstructions)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)

            Button(localized("store_restore.scheduled.cancel", value: "Cancel Restore"), role: .destructive) {
                StoreBackupRestore.cancelScheduledRestore()
                scheduledDirectory = nil
            }
            .font(.subheadline)
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("storeRestore.scheduled")
    }

    private var relaunchInstructions: String {
        #if os(macOS)
        localized("store_restore.scheduled.macos", value: "Quit Pawtrackr (⌘Q), then open it again to finish.")
        #else
        localized("store_restore.scheduled.ios", value: "Close Pawtrackr completely — swipe it up in the app switcher — then open it again to finish.")
        #endif
    }

    private func title(for kind: StoreBackupRestore.Kind) -> String {
        switch kind {
        case .recoveryReset:
            localized("store_restore.kind.reset", value: "Before “Reset Local Data”")
        case .preUpdate:
            localized("store_restore.kind.update", value: "Before an app update")
        case .legacyMove:
            localized("store_restore.kind.legacy", value: "Older storage")
        case .preRestore:
            localized("store_restore.kind.pre_restore", value: "Before your last restore")
        }
    }

    private func icon(for kind: StoreBackupRestore.Kind) -> String {
        switch kind {
        case .recoveryReset: "arrow.counterclockwise.circle"
        case .preUpdate: "arrow.down.app"
        case .legacyMove: "archivebox"
        case .preRestore: "clock.arrow.circlepath"
        }
    }

    private func loadCandidates() async {
        let found = await Task.detached(priority: .userInitiated) {
            StoreBackupRestore.candidates()
        }.value
        candidates = found
        isLoading = false
    }

    private func localized(_ key: String, value: String) -> String {
        AppLocalization.localized(key, value: value)
    }
}
