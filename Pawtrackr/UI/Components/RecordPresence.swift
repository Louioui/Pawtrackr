//
//  RecordPresence.swift
//  Pawtrackr
//
//  Client and Pet details tell other devices they're open, and show a small
//  "Recently open on <device>" chip when another device recently had the
//  same record open. The chip only reads: it never writes to the store, not
//  even when a refresh arrives through .refreshRequired.
//

import SwiftUI
import SwiftData

extension View {
    /// Marks `recordID` as open on this device while the view is on screen:
    /// set on appear, re-stamped every two minutes while visible, cleared
    /// when the view goes away.
    func tracksPresence(recordID: UUID, recordType: String) -> some View {
        modifier(RecordPresenceTracking(recordID: recordID, recordType: recordType))
    }
}

private struct RecordPresenceTracking: ViewModifier {
    let recordID: UUID
    let recordType: String

    func body(content: Content) -> some View {
        content.task(id: recordID) {
            let monitor = CloudKitMonitor.shared
            monitor.setPresence(viewingRecordID: recordID, recordType: recordType)
            // A .task is cancelled when the view disappears, which ends the
            // heartbeat loop; the record is cleared right after.
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(PresencePolicy.heartbeatInterval))
                } catch {
                    break
                }
                monitor.setPresence(viewingRecordID: recordID, recordType: recordType)
            }
            monitor.clearPresence(ifViewing: recordID)
        }
    }
}

extension View {
    /// Puts a "Recently open on <device>" chip above this view while another
    /// device's presence for `recordID` is fresh. The refresh tasks hang on a
    /// container that is always there, so they run while the chip is hidden.
    func showsRecentlyOpenElsewhere(recordID: UUID) -> some View {
        modifier(RecentlyOpenElsewhereChip(recordID: recordID))
    }
}

/// "Recently open on Front Desk iPad". Hidden unless another device's
/// presence for this record was stamped in the last five minutes.
private struct RecentlyOpenElsewhereChip: ViewModifier {
    let recordID: UUID

    @Environment(\.modelContext) private var modelContext
    @Environment(GlobalEventBus.self) private var eventBus
    @State private var deviceName: String?

    func body(content: Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let deviceName {
                Label(PresencePolicy.chipTitle(deviceName: deviceName), systemImage: "ipad.and.iphone")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DS.ColorToken.info)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(DS.ColorToken.info.opacity(0.12), in: Capsule())
                    .padding(.horizontal)
                    .accessibilityIdentifier("presence.recentlyOpenElsewhere")
                    .transition(.opacity)
            }
            content
        }
        .animation(.easeInOut(duration: 0.2), value: deviceName)
        .task(id: recordID) {
            while !Task.isCancelled {
                refresh()
                do {
                    try await Task.sleep(for: .seconds(PresencePolicy.chipRefreshInterval))
                } catch {
                    break
                }
            }
        }
        .task(id: recordID) {
            for await event in eventBus.stream where event == .refreshRequired {
                refresh()
            }
        }
    }

    /// Reads presence through a fresh context: the view's own context keeps
    /// the values it already loaded after CloudKit imports a newer stamp.
    /// Read only; this context is never saved.
    private func refresh() {
        let target: UUID? = recordID
        let context = ModelContext(modelContext.container)
        let descriptor = FetchDescriptor<PresenceRecord>(
            predicate: #Predicate<PresenceRecord> { $0.viewingRecordID == target }
        )
        let records = (try? context.fetch(descriptor)) ?? []
        let match = PresencePolicy.recentlyOpenElsewhere(
            records,
            recordID: recordID,
            currentDeviceID: DeviceIdentity.currentID,
            now: Date()
        )
        let name = match?.deviceName
        if name != deviceName { deviceName = name }
    }
}
