//
//  WalkthroughSetupStopsTests.swift
//  PawtrackrTests
//
//  The two tour stops that point at setup surfaces: the dashboard's Getting
//  Started card and the loyalty preview in Settings > Loyalty. Both anchors
//  used to be attached with no stop pointing at them (the loyalty one on the
//  onboarding cover, where no tour overlay exists).
//

import XCTest
@testable import Pawtrackr

@MainActor
final class WalkthroughSetupStopsTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: AppSettingsKeys.appLanguageOverride)
        super.tearDown()
    }

    func testGettingStartedStopFollowsTheDashboardForOwners() throws {
        let owner = WalkthroughController.tour(for: .ownerManager, context: .practice).map(\.id)
        let dashboard = try XCTUnwrap(owner.firstIndex(of: WalkthroughStepID.dashboard))
        XCTAssertEqual(owner[dashboard + 1], WalkthroughStepID.setupChecklist)

        let step = try XCTUnwrap(WalkthroughController.fullTour().first { $0.id == WalkthroughStepID.setupChecklist })
        XCTAssertEqual(step.anchor, .setupChecklist)
        XCTAssertEqual(step.surface, .dashboard)
        XCTAssertEqual(step.lesson, .appMap)
        XCTAssertTrue(step.skipsWhenTargetMissing, "The card is hidden once every row is done or it was closed.")
        XCTAssertFalse(step.requiresTargetAction || step.allowsTargetInteraction, "Look-only: a tap mustn't open a sheet mid-tour.")

        let frontDesk = WalkthroughController.tour(for: .frontDeskGroomer, context: .practice).map(\.id)
        XCTAssertFalse(frontDesk.contains(WalkthroughStepID.setupChecklist), "Setup is the owner's job.")
    }

    func testLoyaltyStopOpensTheLoyaltySectionAndPointsAtThePreview() throws {
        let step = try XCTUnwrap(WalkthroughController.fullTour().first { $0.id == WalkthroughStepID.loyalty })
        XCTAssertEqual(step.anchor, .loyaltySimulator)
        XCTAssertEqual(step.surface, .settings)
        XCTAssertEqual(step.lesson, .settingsAndSafety)
        XCTAssertTrue(step.isOwnerOnly)

        // The tour opens Settings > Loyalty for it, and spotlights the card,
        // not the whole section. The section as a whole is the ladder stop's.
        XCTAssertEqual(SettingSection.walkthroughSection(for: .loyaltySimulator), .loyalty)
        XCTAssertEqual(SettingSection.loyalty.walkthroughAnchorID, .setLoyalty)
        XCTAssertNotEqual(step.anchor, SettingSection.loyalty.walkthroughAnchorID)
        XCTAssertTrue(WalkthroughOverlayScope.detailAnchors.contains(.loyaltySimulator), "Drawn by the pushed Settings screen on iPad and Mac.")

        let frontDesk = WalkthroughController.tour(for: .frontDeskGroomer, context: .practice).map(\.id)
        XCTAssertFalse(frontDesk.contains(WalkthroughStepID.loyalty))
    }

    func testTheLoyaltyAnchorIsNoLongerOnTheOnboardingCover() throws {
        let onboarding = try source("Pawtrackr/Features/Onboarding/OnboardingView.swift")
        XCTAssertFalse(onboarding.contains("walkthroughTarget(.loyaltySimulator)"), "No tour overlay exists on the onboarding cover.")
        let loyalty = try source("Pawtrackr/Features/Loyalty/LoyaltyManagementView.swift")
        XCTAssertTrue(loyalty.contains("LoyaltySimulatorCard()\n                .walkthroughTarget(.loyaltySimulator)"))
    }

    func testNewStopsCopyInSpanishIsTranslatedAndShort() throws {
        UserDefaults.standard.set(AppLanguageOverride.es.rawValue, forKey: AppSettingsKeys.appLanguageOverride)
        let steps = WalkthroughController.fullTour().filter { [WalkthroughStepID.setupChecklist, WalkthroughStepID.loyalty].contains($0.id) }
        XCTAssertEqual(steps.count, 2)
        for step in steps {
            XCTAssertLessThanOrEqual(step.directive.count, 86, step.directive)
            XCTAssertLessThanOrEqual(step.purpose.count, 190, step.purpose)
            XCTAssertLessThanOrEqual(step.coachTip?.count ?? 0, 150, step.coachTip ?? "")
            for text in [step.title, step.directive, step.purpose, step.coachTip ?? ""] {
                XCTAssertFalse(text.contains(";"), text)
                XCTAssertFalse(text.contains(" — "), text)
            }
        }
        XCTAssertEqual(steps.first { $0.id == WalkthroughStepID.setupChecklist }?.title, "Primeros pasos")
        XCTAssertEqual(steps.first { $0.id == WalkthroughStepID.loyalty }?.title, "Puntos de lealtad")
    }

    func testLadderStopShowsTheLoyaltySectionRightBeforeThePreview() throws {
        let owner = WalkthroughController.tour(for: .ownerManager, context: .practice).map(\.id)
        let ladder = try XCTUnwrap(owner.firstIndex(of: WalkthroughStepID.loyaltyLadder))
        XCTAssertEqual(owner[ladder + 1], WalkthroughStepID.loyalty, "Same Settings screen: the section, then its preview card.")

        let step = try XCTUnwrap(WalkthroughController.fullTour().first { $0.id == WalkthroughStepID.loyaltyLadder })
        XCTAssertEqual(step.anchor, .setLoyalty)
        XCTAssertEqual(SettingSection.walkthroughSection(for: step.anchor), .loyalty)
        XCTAssertTrue(step.isOwnerOnly)
        XCTAssertFalse(step.requiresTargetAction || step.allowsTargetInteraction, "Look-only: Use Rewards 2.0 replaces every reward.")
    }

    func testClientLoyaltyAndDeviceStopsAreInBothTours() throws {
        for role in OnboardingRole.allCases {
            let ids = WalkthroughController.tour(for: role, context: .practice).map(\.id)
            XCTAssertTrue(ids.contains(WalkthroughStepID.clientLoyalty), "\(role)")
            XCTAssertTrue(ids.contains(WalkthroughStepID.devices), "\(role)")
            let iCloud = try XCTUnwrap(ids.firstIndex(of: WalkthroughStepID.iCloud))
            XCTAssertEqual(ids[iCloud + 1], WalkthroughStepID.devices, "\(role)")
        }
        // Client details only open the sample client, so without one the
        // loyalty card stop goes with the other client-detail stops.
        let noSample = WalkthroughTourContext(hasSampleClient: false, hasRealClients: true)
        XCTAssertFalse(WalkthroughController.tour(for: .ownerManager, context: noSample).contains { $0.id == WalkthroughStepID.clientLoyalty })
    }

    func testMergedStopsCopyInSpanishIsTranslated() throws {
        UserDefaults.standard.set(AppLanguageOverride.es.rawValue, forKey: AppSettingsKeys.appLanguageOverride)
        let ids = [WalkthroughStepID.loyaltyLadder, WalkthroughStepID.clientLoyalty, WalkthroughStepID.devices]
        let steps = WalkthroughController.fullTour().filter { ids.contains($0.id) }
        XCTAssertEqual(steps.count, ids.count)
        XCTAssertEqual(steps.first { $0.id == WalkthroughStepID.loyaltyLadder }?.title, "Escalera de lealtad")
        XCTAssertEqual(steps.first { $0.id == WalkthroughStepID.clientLoyalty }?.title, "Saldo de lealtad")
        XCTAssertEqual(steps.first { $0.id == WalkthroughStepID.devices }?.title, "Dispositivos sincronizados")
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
