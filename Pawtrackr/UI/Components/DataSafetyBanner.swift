//
//  DataSafetyBanner.swift
//  Pawtrackr
//
//  Shown when a restore is waiting for a relaunch, when an on-device backup
//  holds clients the live store doesn't (the 1.0.2 recovery-screen reset), or
//  when a previously populated client store opened empty.
//

import SwiftUI

struct DataSafetyBanner: View {
    /// A restore is scheduled for the next launch; shown above everything else
    /// so the user knows edits made now will be set aside.
    let isRestorePending: Bool
    let isDataLossSuspected: Bool
    let message: String
    /// Clients in the backup `StoreBackupRestore` is offering; 0 means no offer.
    let restoreOfferClientCount: Int
    let onReviewRestore: () -> Void
    let onCancelPendingRestore: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        Group {
            if isRestorePending {
                banner(
                    icon: "clock.badge.checkmark",
                    tint: DS.ColorToken.info,
                    title: AppLocalization.localized("store_restore.scheduled.title", value: "Restore ready"),
                    detail: AppLocalization.localized(
                        "data_safety.restore_pending.message",
                        value: "Close Pawtrackr completely and open it again to finish. Anything you change before then will be kept in a separate backup."
                    ),
                    actionTitle: AppLocalization.localized("common.cancel", value: "Cancel"),
                    action: onCancelPendingRestore,
                    isDismissible: false
                )
            } else if restoreOfferClientCount > 0 {
                banner(
                    icon: "clock.arrow.circlepath",
                    tint: DS.ColorToken.warning,
                    title: AppLocalization.localized("data_safety.restore_offer.title", value: "Clients from before the update were found"),
                    detail: String(
                        format: AppLocalization.localized(
                            "data_safety.restore_offer.message_fmt",
                            value: "A backup on this device has %d clients. Review it to bring them back."
                        ),
                        restoreOfferClientCount
                    ),
                    actionTitle: AppLocalization.localized("data_safety.restore_offer.action", value: "Review"),
                    action: onReviewRestore
                )
            } else if isDataLossSuspected {
                banner(
                    icon: "externaldrive.badge.exclamationmark",
                    tint: DS.ColorToken.danger,
                    title: AppLocalization.localized("data_safety.banner.title", value: "Client data needs attention"),
                    detail: message.isEmpty ? fallbackMessage : message,
                    actionTitle: AppLocalization.localized("data_safety.restore_offer.action", value: "Review"),
                    action: onReviewRestore
                )
            }
        }
    }

    private func banner(
        icon: String,
        tint: Color,
        title: String,
        detail: String,
        actionTitle: String,
        action: @escaping () -> Void,
        isDismissible: Bool = true
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button(actionTitle, action: action)
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityIdentifier("dataSafety.review")

            if isDismissible {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppLocalization.localized("data_safety.banner.dismiss", value: "Dismiss"))
                .accessibilityIdentifier("dataSafety.dismiss")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(tint.opacity(0.12))
        .overlay(
            Rectangle().frame(height: 0.5).foregroundStyle(.separator),
            alignment: .bottom
        )
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dataSafety.banner")
    }

    private var fallbackMessage: String {
        AppLocalization.localized(
            "data_safety.banner.message",
            value: "Pawtrackr expected existing clients but opened an empty client store. Don't delete the app or use Start Fresh."
        )
    }
}
