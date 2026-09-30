import XCTest
@testable import Pawtrackr

/// One rule for what a client record lacks (`ClientMissingInfo`), used by
/// the Missing Info filter, the card chip and the profile's "Missing:" note.
final class ClientMissingInfoTests: XCTestCase {
    func testEachGapIsListedInTheProfileOrder() {
        XCTAssertEqual(
            ClientMissingInfo.items(hasEmergencyContact: false, phone: nil, email: nil),
            [.emergencyContact, .ownerPhone, .ownerEmail]
        )
        XCTAssertEqual(ClientMissingInfo.items(hasEmergencyContact: false, phone: "+14155550142", email: "a@b.co"), [.emergencyContact])
        XCTAssertEqual(ClientMissingInfo.items(hasEmergencyContact: true, phone: "+14155550142", email: "a@b.co"), [])
    }

    func testBlankTextCountsAsMissing() {
        XCTAssertEqual(ClientMissingInfo.items(hasEmergencyContact: true, phone: "  ", email: ""), [.ownerPhone, .ownerEmail])
    }

    func testSummaryReadsLikeTheProfileNote() throws {
        XCTAssertNil(ClientMissingInfo.summary([]))
        let summary = try XCTUnwrap(ClientMissingInfo.summary([.emergencyContact]))
        XCTAssertTrue(summary.contains(ClientMissingInfo.emergencyContact.title), summary)
    }

    func testTheFilterTheCardAndTheProfileShareTheRule() throws {
        let root = try repositoryRoot()
        let viewModel = try String(contentsOf: root.appendingPathComponent("Pawtrackr/Features/Clients/ClientsViewModel.swift"), encoding: .utf8)
        XCTAssertTrue(viewModel.contains("filter(ClientMissingInfo.isIncomplete)"))
        let card = try String(contentsOf: root.appendingPathComponent("Pawtrackr/Features/Clients/ClientCard.swift"), encoding: .utf8)
        XCTAssertTrue(card.contains("ClientMissingInfo.items(for: client)"))
        let profile = try String(contentsOf: root.appendingPathComponent("Pawtrackr/UI/Components/EmergencyContactSummaryCard.swift"), encoding: .utf8)
        XCTAssertTrue(profile.contains("ClientMissingInfo.items(hasEmergencyContact:"))
    }

    private func repositoryRoot() throws -> URL {
        var root = URL(fileURLWithPath: #filePath)
        while !FileManager.default.fileExists(atPath: root.appendingPathComponent("Pawtrackr.xcodeproj").path) {
            let parent = root.deletingLastPathComponent()
            guard parent.path != root.path else { throw XCTSkip("Repository sources aren't available.") }
            root = parent
        }
        return root
    }
}
