//
//  WalkthroughSetupStopsTests.swift
//  PawtrackrTests
//
//  The Academy's chapters and the stops that bracket it: the app map it
//  opens on, the Settings stop it ends on, the loyalty card on client
//  details, and chapter names in Spanish.
//

import XCTest
@testable import Pawtrackr

@MainActor
final class WalkthroughSetupStopsTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: AppSettingsKeys.appLanguageOverride)
        super.tearDown()
    }

    func testTheAcademyOpensOnTheAppMapAndEndsInSettings() throws {
        let steps = WalkthroughController.tour(for: .ownerManager, context: .practice)
        let first = try XCTUnwrap(steps.first)
        XCTAssertEqual(first.id, WalkthroughStepID.first)
        XCTAssertEqual(first.anchor, .appNavigation)
        XCTAssertEqual(first.surface, .dashboard)
        XCTAssertFalse(first.allowsTargetInteraction, "Look-only: a tap on the menu moves the tour on, not the app.")

        let last = try XCTUnwrap(steps.last)
        XCTAssertEqual(last.id, WalkthroughStepID.academyHome)
        XCTAssertEqual(last.anchor, .setAbout)
        XCTAssertEqual(last.surface, .settings)
        XCTAssertEqual(SettingSection.walkthroughSection(for: last.anchor), .about, "The tour opens Settings > About for it.")
    }

    func testTheBackupStopOnlyExplainsTheExport() throws {
        let step = try XCTUnwrap(WalkthroughController.fullTour().first { $0.id == WalkthroughStepID.backups })
        XCTAssertEqual(step.anchor, .setData)
        XCTAssertEqual(SettingSection.walkthroughSection(for: step.anchor), .dataExport)
        XCTAssertFalse(step.allowsTargetInteraction, "An export reads the real salon, so the stop never runs one.")
        XCTAssertNil(step.advancesOn)
        XCTAssertFalse(SecureStoreSnapshotExporter.isUserFacingExportEnabled, "If encrypted backups ship, teach them here.")
    }

    func testTheLoyaltyAnchorIsNoLongerOnTheOnboardingCover() throws {
        let onboarding = try source("Pawtrackr/Features/Onboarding/OnboardingView.swift")
        XCTAssertFalse(onboarding.contains("walkthroughTarget(.loyaltySimulator)"), "No tour overlay exists on the onboarding cover.")
        let loyalty = try source("Pawtrackr/Features/Loyalty/LoyaltyManagementView.swift")
        XCTAssertTrue(loyalty.contains("LoyaltySimulatorCard()\n                .walkthroughTarget(.loyaltySimulator)"))
    }

    func testClientLoyaltyStopsAreInBothTours() throws {
        for role in OnboardingRole.allCases {
            let ids = WalkthroughController.tour(for: role, context: .practice).map(\.id)
            XCTAssertTrue(ids.contains(WalkthroughStepID.clientLoyalty), "\(role)")
        }
        // Client details only open the sample client, so without one the
        // loyalty card stop goes with the other client-detail stops.
        let noSample = WalkthroughTourContext(hasSampleClient: false, hasRealClients: true)
        XCTAssertFalse(WalkthroughController.tour(for: .ownerManager, context: noSample).contains { $0.id == WalkthroughStepID.clientLoyalty })
    }

    func testChapterNamesAreTranslated() {
        UserDefaults.standard.set(AppLanguageOverride.es.rawValue, forKey: AppSettingsKeys.appLanguageOverride)
        XCTAssertEqual(
            WalkthroughLesson.allCases.map(\.title),
            ["Panel", "Directorio de clientes", "Perfiles y mascotas", "Visitas y pagos", "Estadísticas y respaldos"]
        )
        UserDefaults.standard.set(AppLanguageOverride.en.rawValue, forKey: AppSettingsKeys.appLanguageOverride)
        XCTAssertEqual(
            WalkthroughLesson.allCases.map(\.title),
            ["Dashboard", "Client Directory", "Profiles & Pets", "Visits & Payments", "Insights & Backups"]
        )
    }

    func testMissionCopyInSpanishNamesTheRealButtons() throws {
        UserDefaults.standard.set(AppLanguageOverride.es.rawValue, forKey: AppSettingsKeys.appLanguageOverride)
        let steps = Dictionary(uniqueKeysWithValues: WalkthroughController.fullTour().map { ($0.id, $0) })
        XCTAssertTrue(try XCTUnwrap(steps[WalkthroughStepID.checkIn]?.action).contains("Registrar entrada"))
        XCTAssertTrue(try XCTUnwrap(steps[WalkthroughStepID.checkOut]?.action).contains("Registrar salida"))
        XCTAssertTrue(try XCTUnwrap(steps[WalkthroughStepID.clientsTab]?.action).contains("Clientes"))
        XCTAssertTrue(try XCTUnwrap(steps[WalkthroughStepID.insightsTab]?.action).contains("Estadísticas"))
    }

    private func source(_ relativePath: String) throws -> String {
        var root = URL(fileURLWithPath: #filePath)
        while !FileManager.default.fileExists(atPath: root.appendingPathComponent("Pawtrackr.xcodeproj").path) {
            let parent = root.deletingLastPathComponent()
            guard parent.path != root.path else { throw XCTSkip("Repository sources aren't available.") }
            root = parent
        }
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
