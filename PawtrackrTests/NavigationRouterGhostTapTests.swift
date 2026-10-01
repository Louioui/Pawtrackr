//
//  NavigationRouterGhostTapTests.swift
//  PawtrackrTests
//
//  Two client cards tapped in the same instant (or one tapped twice) must
//  push one client screen, not stack two that Back then walks through.
//

import XCTest
import SwiftData
@testable import Pawtrackr

@MainActor
final class NavigationRouterGhostTapTests: XCTestCase {
    private var container: ModelContainer!
    private var first: Client!
    private var second: Client!
    private var router: NavigationRouter!
    private var clock = Date(timeIntervalSince1970: 1_750_000_000)

    override func setUpWithError() throws {
        try super.setUpWithError()
        let schema = Schema(PawtrackrSchema.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [config])
        first = Client(firstName: "Ada", lastName: "First")
        second = Client(firstName: "Bo", lastName: "Second")
        container.mainContext.insert(first)
        container.mainContext.insert(second)
        try container.mainContext.save()

        router = NavigationRouter()
        router.activeNavigationItem = .clients
        router.now = { [unowned self] in self.clock }
    }

    override func tearDownWithError() throws {
        router = nil
        first = nil
        second = nil
        container = nil
        try super.tearDownWithError()
    }

    func testTwoCardsTappedTogetherPushOneScreen() {
        router.navigateToClient(first)
        router.navigateToClient(second)

        XCTAssertEqual(router.clientsPath.count, 1)
    }

    func testTheSameCardTappedTwicePushesOnce() {
        router.navigateToClient(first)
        clock.addTimeInterval(0.1)
        router.navigateToClient(first)

        XCTAssertEqual(router.clientsPath.count, 1)
    }

    func testAMashOfTapsPushesOnce() {
        for index in 0..<50 {
            router.navigateToClient(index.isMultiple(of: 2) ? first : second)
            clock.addTimeInterval(0.005)
        }

        XCTAssertEqual(router.clientsPath.count, 1)
    }

    func testATapAfterTheWindowPushes() {
        router.navigateToClient(first)
        clock.addTimeInterval(NavigationRouter.ghostTapWindow + 0.01)
        router.navigateToClient(second)

        XCTAssertEqual(router.clientsPath.count, 2)
    }

    func testBackRearmsAtOnce() {
        router.navigateToClient(first)
        router.pop()
        router.navigateToClient(second)

        XCTAssertEqual(router.clientsPath.count, 1)
    }

    /// A swipe back (finished, not cancelled) writes the shorter path
    /// through the NavigationStack binding rather than calling `pop()`.
    func testSwipeBackThroughTheBindingRearms() {
        router.navigateToClient(first)
        var path = router.clientsPath
        path.removeLast()
        router.clientsPath = path

        router.navigateToClient(second)

        XCTAssertEqual(router.clientsPath.count, 1)
    }

    func testOpeningAClientFromElsewhereAfterPopToRootIsNotDropped() {
        router.navigateToClient(first)
        router.popClientsToRoot()
        router.navigateToClient(second)

        XCTAssertEqual(router.clientsPath.count, 1)
    }
}
