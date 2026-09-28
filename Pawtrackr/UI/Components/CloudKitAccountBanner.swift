//
//  CloudKitAccountBanner.swift
//  Pawtrackr
//
//  Top-of-screen banner for iCloud backup problems, most serious first:
//  local-only mode or uploads iCloud keeps rejecting (red, can't be
//  dismissed), then full iCloud storage, then account problems, then changes
//  that have waited past the upload grace period.
//
//  The red banners carry Export clients and Share support report, because
//  at that point the device holds the only copy. Account banners open
//  Settings (iOS) / System Settings (macOS) so the groomer can fix them.
//

import SwiftUI
import SwiftData
#if canImport(UIKit) && !targetEnvironment(macCatalyst)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct CloudKitAccountBanner: View {
    @Environment(\.modelContext) private var modelContext
    @State private var monitor = CloudKitMonitor.shared
    @State private var dismissedFingerprint: String?
    @State private var clientExport: ExportDocument?
    @State private var supportReport: String?
    @State private var isPreparingExport = false
    @State private var actionError: String?

    var body: some View {
        Group {
            if let info = bannerInfo, info.fingerprint != dismissedFingerprint {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: info.icon)
                            .font(.title3)
                            .foregroundStyle(info.tint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(info.title).font(.subheadline.weight(.semibold))
                            Text(info.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        if let actionTitle = info.actionTitle {
                            Button {
                                openSettings()
                            } label: {
                                Text(actionTitle)
                                    .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        if info.isDismissible {
                            Button {
                                dismissedFingerprint = info.fingerprint
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(NSLocalizedString("common.dismiss", value: "Dismiss", comment: ""))
                        }
                    }

                    if info.offersDataActions {
                        dataActions
                            .padding(.leading, 34)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(info.tint.opacity(0.12))
                .overlay(
                    Rectangle().frame(height: 0.5).foregroundStyle(.separator),
                    alignment: .bottom
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                // Prepared up front so "Share support report" is one tap.
                .task(id: info.fingerprint) {
                    guard info.offersDataActions else { return }
                    supportReport = await SupportService.shared.generateReport(context: modelContext).content
                }
            }
        }
        // Re-arm dismissal when the banner's identity changes (or it goes away).
        // Without this, a banner dismissed once stays hidden even after the same
        // condition (same fingerprint) recurs later in the session.
        .onChange(of: bannerInfo?.fingerprint) { oldValue, newValue in
            if oldValue != newValue {
                dismissedFingerprint = nil
                clientExport = nil
                supportReport = nil
                actionError = nil
            }
        }
    }

    /// Stacked, not side by side: two labelled buttons don't fit next to each
    /// other at iPhone width.
    private var dataActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let clientExport {
                ShareLink(
                    item: clientExport,
                    preview: SharePreview(clientExport.filename, icon: Image(systemName: "doc.text.fill"))
                ) {
                    Label(
                        String(
                            format: AppLocalization.localized("settings.export.share_fmt", value: "Share %@"),
                            clientExport.filename
                        ),
                        systemImage: "square.and.arrow.up"
                    )
                    .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            } else {
                Button {
                    prepareClientExport()
                } label: {
                    Label(
                        AppLocalization.localized("cloudkit.banner.action.export_clients", value: "Export clients"),
                        systemImage: "person.3.sequence.fill"
                    )
                    .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isPreparingExport)
            }

            if let supportReport {
                ShareLink(item: supportReport) {
                    Label(
                        AppLocalization.localized("cloudkit.banner.action.send_support", value: "Share support report"),
                        systemImage: "lifepreserver"
                    )
                    .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                ProgressView()
                    .controlSize(.small)
            }

            if let actionError {
                Text(actionError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var bannerInfo: BannerInfo? {
        // Tests and in-memory runs have iCloud off on purpose.
        if monitor.mode == .disabled { return nil }

        if monitor.mode.isLocalOnlyFallback {
            return BannerInfo(
                fingerprint: "localOnly",
                icon: "icloud.slash",
                tint: .red,
                title: AppLocalization.localized("cloudkit.banner.local_only.title", value: "iCloud backup is off on this device"),
                message: AppLocalization.localized(
                    "cloudkit.banner.local_only.message",
                    value: "Pawtrackr couldn't start iCloud sync, so your clients are saved only here."
                ),
                actionTitle: nil,
                isDismissible: false,
                offersDataActions: true
            )
        }

        // Signed in, but iCloud refuses Pawtrackr: almost always the per-app
        // iCloud switch. Red like a rejection, but with the switch to check.
        if monitor.isShowingUploadRejection, monitor.iCloudAppAccessMayBeDisabled {
            return BannerInfo(
                fingerprint: "appAccessBlocked",
                icon: "exclamationmark.icloud.fill",
                tint: .red,
                title: NSLocalizedString("cloudkit.banner.app_access.title", value: "Check iCloud access", comment: ""),
                message: AppLocalization.localized(
                    "cloudkit.error.setup_failed",
                    value: "iCloud sync couldn't start even though you're signed in. Check that Pawtrackr is turned on for iCloud in Settings, then reopen the app."
                ),
                actionTitle: NSLocalizedString("common.settings", value: "Settings", comment: ""),
                isDismissible: false,
                offersDataActions: true
            )
        }

        if monitor.isShowingUploadRejection, case .failing(_, let disposition) = monitor.backupStatus {
            return BannerInfo(
                fingerprint: "uploadRejected",
                icon: "xmark.icloud.fill",
                tint: .red,
                title: SyncFailureCopy.severeTitle(for: disposition),
                message: AppLocalization.localized(
                    "cloudkit.banner.rejected.message",
                    value: "Your clients are on this device but are NOT backed up. Don't delete the app."
                ),
                actionTitle: nil,
                isDismissible: false,
                offersDataActions: true
            )
        }

        if monitor.accountState == .available, monitor.quotaExceeded {
            return BannerInfo(
                fingerprint: "quotaExceeded",
                icon: "exclamationmark.icloud.fill",
                tint: .red,
                title: NSLocalizedString("cloudkit.banner.quota.title", value: "iCloud storage is full", comment: ""),
                message: NSLocalizedString("cloudkit.banner.quota.message", value: "Changes are saving locally until iCloud storage is cleared.", comment: "")
                    + " " + storageSteps,
                actionTitle: NSLocalizedString("common.settings", value: "Settings", comment: ""),
                isDismissible: false
            )
        }

        switch monitor.accountState {
        case .noAccount:
            return BannerInfo(
                fingerprint: "noAccount",
                icon: "icloud.slash",
                tint: .orange,
                title: NSLocalizedString("cloudkit.banner.signed_out.title", value: "Signed out of iCloud", comment: ""),
                message: SyncFailureCopy.signedOutMessage,
                actionTitle: NSLocalizedString("common.settings", value: "Settings", comment: ""),
                isDismissible: true
            )
        case .restricted:
            return BannerInfo(
                fingerprint: "restricted",
                icon: "lock.icloud",
                tint: .orange,
                title: NSLocalizedString("cloudkit.banner.restricted.title", value: "iCloud is restricted", comment: ""),
                message: NSLocalizedString("cloudkit.banner.restricted.message", value: "Restrictions or parental controls are blocking iCloud sync.", comment: ""),
                actionTitle: NSLocalizedString("common.settings", value: "Settings", comment: ""),
                isDismissible: true
            )
        case .temporarilyUnavailable:
            return BannerInfo(
                fingerprint: "temporarilyUnavailable",
                icon: "icloud.slash",
                tint: .orange,
                title: NSLocalizedString("cloudkit.banner.temp_unavailable.title", value: "iCloud unavailable", comment: ""),
                message: NSLocalizedString("cloudkit.banner.temp_unavailable.message", value: "Sign in again or wait — iCloud is temporarily unavailable.", comment: ""),
                actionTitle: NSLocalizedString("common.settings", value: "Settings", comment: ""),
                isDismissible: true
            )
        case .available where monitor.iCloudAppAccessMayBeDisabled:
            return BannerInfo(
                fingerprint: "appAccessDisabled",
                icon: "exclamationmark.icloud.fill",
                tint: .orange,
                title: NSLocalizedString("cloudkit.banner.app_access.title", value: "Check iCloud access", comment: ""),
                message: NSLocalizedString("cloudkit.banner.app_access.message", value: "iCloud is signed in, but app access may be disabled in Settings.", comment: ""),
                actionTitle: NSLocalizedString("common.settings", value: "Settings", comment: ""),
                isDismissible: true
            )
        case .available where monitor.hasUploadsPendingPastGrace:
            // Only past the grace period: uploads normally trail a save by
            // seconds to minutes, and flashing this after every save taught
            // groomers to ignore it.
            return BannerInfo(
                fingerprint: "pending",
                icon: "icloud.and.arrow.up",
                tint: .orange,
                title: NSLocalizedString("cloudkit.banner.pending.title", value: "iCloud upload pending", comment: ""),
                message: NSLocalizedString("cloudkit.banner.pending.message", value: "Changes are saving locally and will upload when iCloud is ready.", comment: ""),
                actionTitle: nil,
                isDismissible: false
            )
        default:
            return nil
        }
    }

    /// There is no public URL for iCloud storage, so the banner opens
    /// Settings and says where to go from there.
    private var storageSteps: String {
        #if os(macOS)
        AppLocalization.localized(
            "cloudkit.banner.quota.steps_mac",
            value: "To free up space, open System Settings, click your name, then iCloud > Manage."
        )
        #else
        AppLocalization.localized(
            "cloudkit.banner.quota.steps_ios",
            value: "To free up space, open Settings, tap your name, then iCloud > Manage Account Storage."
        )
        #endif
    }

    private func openSettings() {
        #if canImport(UIKit) && !targetEnvironment(macCatalyst)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #elseif canImport(AppKit)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preferences.AppleIDPrefPane") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }

    /// Same export as Settings > Data Export, so the file matches what the
    /// groomer would get there.
    private func prepareClientExport() {
        actionError = nil
        isPreparingExport = true
        defer { isPreparingExport = false }
        do {
            clientExport = try ExportService.shared.exportClientsToCSV(modelContext: modelContext)
        } catch {
            actionError = String(
                format: AppLocalization.localized("settings.export.failed_fmt", value: "Export failed: %@"),
                error.localizedDescription
            )
        }
    }

    private struct BannerInfo {
        let fingerprint: String
        let icon: String
        let tint: Color
        let title: String
        let message: String
        let actionTitle: String?
        let isDismissible: Bool
        var offersDataActions = false
    }
}
