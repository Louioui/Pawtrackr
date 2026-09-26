//
//  DataSafetyBanner.swift
//  Pawtrackr
//
//  Persistent warning shown when the app detects that a previously populated
//  client store opened as empty after an app update.
//

import SwiftUI

struct DataSafetyBanner: View {
    let isPresented: Bool
    let message: String
    let recoveryDetail: String

    var body: some View {
        Group {
            if isPresented {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "externaldrive.badge.exclamationmark")
                        .font(.title3)
                        .foregroundStyle(DS.ColorToken.danger)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(AppLocalization.localized("data_safety.banner.title", value: "Client data needs attention"))
                            .font(.subheadline.weight(.semibold))
                        Text(message.isEmpty ? fallbackMessage : message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !recoveryDetail.isEmpty {
                            Text(recoveryDetail)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }

                    Spacer(minLength: 8)

                    Button {
                        openSettings()
                    } label: {
                        Text(AppLocalization.localized("data_safety.banner.action", value: "Open Settings"))
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(DS.ColorToken.danger.opacity(0.12))
                .overlay(
                    Rectangle().frame(height: 0.5).foregroundStyle(.separator),
                    alignment: .bottom
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("dataSafety.banner")
            }
        }
    }

    private var fallbackMessage: String {
        AppLocalization.localized(
            "data_safety.banner.message",
            value: "Pawtrackr expected existing clients but opened an empty client store. Do not delete the app or use Start Fresh until you export or recover the data."
        )
    }

    private func openSettings() {
        NotificationCenter.default.post(name: .selectNavigationItem, object: nil, userInfo: [
            NavigationSelectionKey.item.rawValue: NavigationItem.settings.rawValue,
            NavigationSelectionKey.resetPath.rawValue: true
        ])
    }
}
