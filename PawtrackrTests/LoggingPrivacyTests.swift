import XCTest

final class LoggingPrivacyTests: XCTestCase {
    func testSensitiveDashboardAndPruningLogsUseExplicitPrivatePrivacy() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let dashboardRepository = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Pawtrackr/Features/Dashboard/DashboardRepository.swift"),
            encoding: .utf8
        )
        let dataPruningService = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Pawtrackr/Core/Storage/DataPruningService.swift"),
            encoding: .utf8
        )
        let authenticationViewModel = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Pawtrackr/Features/Onboarding/AuthenticationViewModel.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(
            dashboardRepository.contains(#"\(visit.pet?.name ?? "unknown")"#),
            "Pet names in dashboard repository logs must use explicit private privacy."
        )
        XCTAssertFalse(
            dataPruningService.contains(#"\(file.lastPathComponent)"#),
            "Pruned asset filenames may contain client or receipt details and must use explicit private privacy."
        )
        XCTAssertFalse(
            dataPruningService.contains(#"\(folder.lastPathComponent)"#),
            "Pruning folder names should use explicit privacy annotations in logs."
        )
        XCTAssertFalse(
            authenticationViewModel.contains(#"User fetch failed for email lookup: \(String(describing: error))"#),
            "Auth lookup errors can include the email predicate and must use explicit private privacy."
        )
        XCTAssertFalse(
            authenticationViewModel.contains(#"\(label) save failed: \(String(describing: error))"#),
            "Auth save labels and errors must use explicit privacy annotations."
        )
    }
}
