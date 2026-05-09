//
//  CloudKitAccountBanner.swift
//  Pawtrackr
//
//  Top-of-screen banner shown when the user is signed out of iCloud,
//  iCloud storage is full, or sync has hit a hard error.
//
//  Hidden when everything is healthy. Tapping the banner opens system
//  Settings (iOS) / System Settings.app (macOS) so the user can fix it.
//

import SwiftUI
#if canImport(UIKit) && !targetEnvironment(macCatalyst)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct CloudKitAccountBanner: View {
    @State private var monitor = CloudKitMonitor.shared
    @State private var dismissedFingerprint: String?

    var body: some View {
        if let info = bannerInfo, info.fingerprint != dismissedFingerprint {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: info.icon)
                    .font(.title3)
                    .foregroundStyle(info.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(info.title).font(.subheadline.weight(.semibold))
                    Text(info.message).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if let actionTitle = info.actionTitle {
                    Button {
                        open(info.action)
                    } label: {
                        Text(actionTitle)
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
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
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(info.tint.opacity(0.12))
            .overlay(
                Rectangle().frame(height: 0.5).foregroundStyle(.separator),
                alignment: .bottom
            )
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var bannerInfo: BannerInfo? {
        switch monitor.accountState {
        case .noAccount:
            return BannerInfo(
                fingerprint: "noAccount",
                icon: "icloud.slash",
                tint: .orange,
                title: NSLocalizedString("cloudkit.banner.signed_out.title", value: "Signed out of iCloud", comment: ""),
                message: NSLocalizedString("cloudkit.banner.signed_out.message", value: "Your data is only on this device. Sign in to back it up and sync.", comment: ""),
                actionTitle: NSLocalizedString("common.settings", value: "Settings", comment: ""),
                action: .settings
            )
        case .restricted:
            return BannerInfo(
                fingerprint: "restricted",
                icon: "lock.icloud",
                tint: .orange,
                title: NSLocalizedString("cloudkit.banner.restricted.title", value: "iCloud is restricted", comment: ""),
                message: NSLocalizedString("cloudkit.banner.restricted.message", value: "Restrictions or parental controls are blocking iCloud sync.", comment: ""),
                actionTitle: NSLocalizedString("common.settings", value: "Settings", comment: ""),
                action: .settings
            )
        case .temporarilyUnavailable:
            return BannerInfo(
                fingerprint: "temporarilyUnavailable",
                icon: "icloud.slash",
                tint: .orange,
                title: NSLocalizedString("cloudkit.banner.temp_unavailable.title", value: "iCloud unavailable", comment: ""),
                message: NSLocalizedString("cloudkit.banner.temp_unavailable.message", value: "Sign in again or wait — iCloud is temporarily unavailable.", comment: ""),
                actionTitle: NSLocalizedString("common.settings", value: "Settings", comment: ""),
                action: .settings
            )
        case .available where monitor.quotaExceeded:
            return BannerInfo(
                fingerprint: "quotaExceeded",
                icon: "exclamationmark.icloud.fill",
                tint: .red,
                title: NSLocalizedString("cloudkit.banner.quota.title", value: "iCloud storage is full", comment: ""),
                message: NSLocalizedString("cloudkit.banner.quota.message", value: "Free up space or upgrade so new visits and photos can sync.", comment: ""),
                actionTitle: NSLocalizedString("cloudkit.banner.quota.action", value: "Manage Storage", comment: ""),
                action: .iCloudStorage
            )
        case .available where monitor.iCloudAppAccessMayBeDisabled:
            return BannerInfo(
                fingerprint: "appAccessDisabled",
                icon: "exclamationmark.icloud.fill",
                tint: .orange,
                title: NSLocalizedString("cloudkit.banner.app_access.title", value: "Check iCloud access", comment: ""),
                message: NSLocalizedString("cloudkit.banner.app_access.message", value: "iCloud is signed in, but app access may be disabled in Settings.", comment: ""),
                actionTitle: NSLocalizedString("common.settings", value: "Settings", comment: ""),
                action: .settings
            )
        case .available:
            if let message = monitor.lastErrorMessage, case .error = monitor.syncState {
                return BannerInfo(
                    fingerprint: "syncError-\(message)",
                    icon: "xmark.icloud.fill",
                    tint: .red,
                    title: NSLocalizedString("cloudkit.banner.sync_error.title", value: "iCloud sync needs attention", comment: ""),
                    message: message,
                    actionTitle: NSLocalizedString("common.settings", value: "Settings", comment: ""),
                    action: .settings
                )
            }
            return nil
        default:
            return nil
        }
    }

    private func open(_ action: BannerAction) {
        #if canImport(UIKit) && !targetEnvironment(macCatalyst)
        let urlString: String
        switch action {
        case .settings:
            urlString = UIApplication.openSettingsURLString
        case .iCloudStorage:
            urlString = "App-prefs:CASTLE&path=STORAGE_MANAGEMENT"
        }
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url) { success in
                if !success, action != .settings, let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsURL)
                }
            }
        }
        #elseif canImport(AppKit)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preferences.AppleIDPrefPane") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }

    private struct BannerInfo {
        let fingerprint: String
        let icon: String
        let tint: Color
        let title: String
        let message: String
        let actionTitle: String?
        let action: BannerAction
    }

    private enum BannerAction: Equatable {
        case settings
        case iCloudStorage
    }
}
