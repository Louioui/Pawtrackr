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
                if info.actionTitle != nil {
                    Button {
                        openSystemSettings()
                    } label: {
                        Text(info.actionTitle ?? "")
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
                actionTitle: NSLocalizedString("common.settings", value: "Settings", comment: "")
            )
        case .restricted:
            return BannerInfo(
                fingerprint: "restricted",
                icon: "lock.icloud",
                tint: .orange,
                title: NSLocalizedString("cloudkit.banner.restricted.title", value: "iCloud is restricted", comment: ""),
                message: NSLocalizedString("cloudkit.banner.restricted.message", value: "Restrictions or parental controls are blocking iCloud sync.", comment: ""),
                actionTitle: NSLocalizedString("common.settings", value: "Settings", comment: "")
            )
        case .temporarilyUnavailable:
            return BannerInfo(
                fingerprint: "temporarilyUnavailable",
                icon: "icloud.slash",
                tint: .orange,
                title: NSLocalizedString("cloudkit.banner.temp_unavailable.title", value: "iCloud unavailable", comment: ""),
                message: NSLocalizedString("cloudkit.banner.temp_unavailable.message", value: "Sign in again or wait — iCloud is temporarily unavailable.", comment: ""),
                actionTitle: NSLocalizedString("common.settings", value: "Settings", comment: "")
            )
        case .available where monitor.quotaExceeded:
            return BannerInfo(
                fingerprint: "quotaExceeded",
                icon: "exclamationmark.icloud.fill",
                tint: .red,
                title: NSLocalizedString("cloudkit.banner.quota.title", value: "iCloud storage is full", comment: ""),
                message: NSLocalizedString("cloudkit.banner.quota.message", value: "Free up space or upgrade so new visits and photos can sync.", comment: ""),
                actionTitle: NSLocalizedString("common.settings", value: "Settings", comment: "")
            )
        default:
            return nil
        }
    }

    private func openSystemSettings() {
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

    private struct BannerInfo {
        let fingerprint: String
        let icon: String
        let tint: Color
        let title: String
        let message: String
        let actionTitle: String?
    }
}
