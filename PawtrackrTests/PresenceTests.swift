import XCTest
import SwiftData
@testable import Pawtrackr

/// Client and Pet details write "this record is open here" for other devices,
/// and show "Recently open on <device>" when another device had it open.
/// Every write to a mirrored row uploads to every device, so a repeat call
/// with nothing new must write nothing.
@MainActor
final class PresenceTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    let thisDevice = UUID()
    let otherDevice = UUID()
    let clientID = UUID()
    let start = Date(timeIntervalSince1970: 1_000_000)

    private var savedLanguageOverride: String?

    override func setUpWithError() throws {
        savedLanguageOverride = UserDefaults.standard.string(forKey: AppSettingsKeys.appLanguageOverride)
        UserDefaults.standard.set(AppLanguageOverride.en.rawValue, forKey: AppSettingsKeys.appLanguageOverride)
        let schema = Schema(PawtrackrSchema.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
    }

    override func tearDownWithError() throws {
        if let savedLanguageOverride {
            UserDefaults.standard.set(savedLanguageOverride, forKey: AppSettingsKeys.appLanguageOverride)
        } else {
            UserDefaults.standard.removeObject(forKey: AppSettingsKeys.appLanguageOverride)
        }
        container = nil
        context = nil
    }

    private func apply(_ recordID: UUID?, type: String? = "client", name: String = "Front Desk iPad", at offset: TimeInterval) throws -> Bool {
        try PresencePolicy.apply(
            in: context,
            deviceID: thisDevice,
            deviceName: name,
            viewingRecordID: recordID,
            recordType: recordID == nil ? nil : type,
            now: start.addingTimeInterval(offset)
        )
    }

    private func records() throws -> [PresenceRecord] {
        try ModelContext(container).fetch(FetchDescriptor<PresenceRecord>())
    }

    // MARK: - Writes

    func testSameValuesTwiceSaveOnce() throws {
        XCTAssertTrue(try apply(clientID, at: 0), "Opening a client writes this device's presence.")
        XCTAssertFalse(try apply(clientID, at: 5), "The same values again, before a heartbeat is due, write nothing.")
        XCTAssertFalse(context.hasChanges)

        let stored = try XCTUnwrap(records().first)
        XCTAssertEqual(stored.updatedAt, start, "No stamp moves without a write.")
        XCTAssertEqual(try records().count, 1)
    }

    func testHeartbeatMovesOnlyTheStampWhenDue() throws {
        XCTAssertTrue(try apply(clientID, at: 0))
        XCTAssertFalse(try apply(clientID, at: PresencePolicy.heartbeatDueAge - 1))
        XCTAssertTrue(try apply(clientID, at: PresencePolicy.heartbeatInterval), "The two-minute heartbeat keeps the record fresh.")

        let stored = try XCTUnwrap(records().first)
        XCTAssertEqual(stored.updatedAt, start.addingTimeInterval(PresencePolicy.heartbeatInterval))
        XCTAssertEqual(stored.viewingRecordID, clientID)
    }

    func testOpeningAnotherRecordUpdatesTheSameRow() throws {
        let petID = UUID()
        XCTAssertTrue(try apply(clientID, at: 0))
        XCTAssertTrue(try apply(petID, type: "pet", at: 3))

        let all = try records()
        XCTAssertEqual(all.count, 1, "One record per device, updated in place.")
        XCTAssertEqual(all.first?.viewingRecordID, petID)
        XCTAssertEqual(all.first?.recordType, "pet")
    }

    func testClearingWritesOnceAndClearingNothingWritesNothing() throws {
        XCTAssertFalse(try apply(nil, at: 0), "With no record yet, clearing inserts nothing.")
        XCTAssertTrue(try records().isEmpty)

        XCTAssertTrue(try apply(clientID, at: 1))
        XCTAssertTrue(try apply(nil, at: 2), "Closing the screen clears the record.")
        XCTAssertFalse(try apply(nil, at: 500), "No heartbeat for a cleared record.")

        let stored = try XCTUnwrap(records().first)
        XCTAssertNil(stored.viewingRecordID)
        XCTAssertNil(stored.recordType)
        XCTAssertEqual(stored.updatedAt, start.addingTimeInterval(2))
    }

    func testDecisionTable() {
        func decide(existing: (String, UUID?, String?, TimeInterval)?, name: String = "iPad", id: UUID?, type: String? = "client", at now: TimeInterval) -> PresencePolicy.Decision {
            PresencePolicy.decision(
                existingDeviceName: existing?.0,
                existingViewingRecordID: existing?.1,
                existingRecordType: existing?.2,
                existingUpdatedAt: existing.map { start.addingTimeInterval($0.3) },
                hasExisting: existing != nil,
                deviceName: name,
                viewingRecordID: id,
                recordType: id == nil ? nil : type,
                now: start.addingTimeInterval(now)
            )
        }

        XCTAssertEqual(decide(existing: nil, id: clientID, at: 0), .insert)
        XCTAssertEqual(decide(existing: nil, id: nil, at: 0), .skip)
        XCTAssertEqual(decide(existing: ("iPad", clientID, "client", 0), id: clientID, at: 30), .skip)
        XCTAssertEqual(decide(existing: ("iPad", clientID, "client", 0), id: clientID, at: 90), .update)
        XCTAssertEqual(decide(existing: ("iPad", clientID, "client", 0), name: "Back iPad", id: clientID, at: 30), .update, "A renamed device updates its record.")
        XCTAssertEqual(decide(existing: ("iPad", nil, nil, 0), id: nil, at: 900), .skip)
    }

    // MARK: - Chip

    private func record(device: UUID, name: String = "Front Desk iPad", viewing: UUID?, ageSeconds: TimeInterval) -> PresenceRecord {
        let record = PresenceRecord(deviceID: device, deviceName: name)
        record.viewingRecordID = viewing
        record.recordType = "client"
        record.updatedAt = start.addingTimeInterval(-ageSeconds)
        return record
    }

    func testChipShowsAnotherDevicesFreshRecordForThisClient() {
        let match = PresencePolicy.recentlyOpenElsewhere(
            [record(device: otherDevice, viewing: clientID, ageSeconds: 60)],
            recordID: clientID,
            currentDeviceID: thisDevice,
            now: start
        )
        XCTAssertEqual(match?.deviceName, "Front Desk iPad")
        XCTAssertEqual(PresencePolicy.chipTitle(deviceName: "Front Desk iPad"), "Recently open on Front Desk iPad")
    }

    func testChipHidesThisDeviceStaleRecordsAndOtherRecords() {
        XCTAssertNil(PresencePolicy.recentlyOpenElsewhere(
            [record(device: thisDevice, viewing: clientID, ageSeconds: 10)],
            recordID: clientID, currentDeviceID: thisDevice, now: start
        ), "This device's own record never shows.")
        XCTAssertNil(PresencePolicy.recentlyOpenElsewhere(
            [record(device: otherDevice, viewing: clientID, ageSeconds: PresencePolicy.chipFreshness + 1)],
            recordID: clientID, currentDeviceID: thisDevice, now: start
        ), "Older than five minutes is not recent.")
        XCTAssertNil(PresencePolicy.recentlyOpenElsewhere(
            [record(device: otherDevice, viewing: UUID(), ageSeconds: 10)],
            recordID: clientID, currentDeviceID: thisDevice, now: start
        ), "Another client being open elsewhere doesn't count.")
        XCTAssertNil(PresencePolicy.recentlyOpenElsewhere(
            [record(device: otherDevice, viewing: nil, ageSeconds: 10)],
            recordID: clientID, currentDeviceID: thisDevice, now: start
        ), "A cleared record doesn't count.")
    }

    func testChipPicksTheNewestMatchingRecord() {
        let third = UUID()
        let match = PresencePolicy.recentlyOpenElsewhere(
            [
                record(device: otherDevice, name: "Front Desk iPad", viewing: clientID, ageSeconds: 200),
                record(device: third, name: "Back Room Mac", viewing: clientID, ageSeconds: 20)
            ],
            recordID: clientID, currentDeviceID: thisDevice, now: start
        )
        XCTAssertEqual(match?.deviceName, "Back Room Mac")
    }

    func testChipTitleFallsBackForUnnamedDevices() {
        let unnamed = PresencePolicy.chipTitle(deviceName: "  ")
        XCTAssertEqual(unnamed, PresencePolicy.chipTitle(deviceName: "Unknown Device"))
        XCTAssertFalse(unnamed.contains("  "))
        XCTAssertFalse(unnamed.lowercased().contains("live"))
        XCTAssertFalse(unnamed.lowercased().contains("now"))
    }
}
