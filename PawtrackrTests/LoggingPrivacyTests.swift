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

    func testInsightsRevenueSurfaceUsesPrivacyBlur() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let insightsView = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Pawtrackr/Features/Insights/InsightsView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            insightsView.contains(".privacyBlur()"),
            "Insights shows revenue and average-ticket data, so it must blur when the scene resigns active."
        )
    }

    func testDashboardRevenueSurfaceUsesPrivacyBlur() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let dashboardView = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Pawtrackr/Features/Dashboard/DashboardView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            dashboardView.contains(".privacyBlur()"),
            "Dashboard shows today and 7-day revenue data, so it must blur when the scene resigns active."
        )
    }

    func testRecentHistoryRevenueSurfaceUsesPrivacyBlur() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let recentHistoryView = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Pawtrackr/Features/Dashboard/RecentHistoryView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            recentHistoryView.contains(".privacyBlur()"),
            "Recent History shows visit totals and revenue summaries, so it must blur when the scene resigns active."
        )
    }
}
