//
//  InsightsAccessPolicyTests.swift
//  PawtrackrTests
//
//  Guards the Insights premium gate: locked only for an explicit non-entitled
//  user outside the guided tour, so paying users never see a lock flash and
//  the tour can keep teaching the charts on demo data.
//

import XCTest
@testable import Pawtrackr

final class InsightsAccessPolicyTests: XCTestCase {

    func testNotEntitledLocksOutsideWalkthrough() {
        XCTAssertTrue(InsightsAccessPolicy.isLocked(status: .notEntitled, isWalkthroughActive: false))
    }

    func testGuidedTourBypassesLockSoDemoChartsStayTeachable() {
        XCTAssertFalse(InsightsAccessPolicy.isLocked(status: .notEntitled, isWalkthroughActive: true))
    }

    func testEntitledNeverLocks() {
        XCTAssertFalse(InsightsAccessPolicy.isLocked(
            status: .entitled(inTrial: true, expiration: .distantFuture),
            isWalkthroughActive: false
        ))
        XCTAssertFalse(InsightsAccessPolicy.isLocked(
            status: .entitled(inTrial: false, expiration: nil),
            isWalkthroughActive: false
        ))
    }

    func testUnknownStaysUnlockedToAvoidLockFlashAtLaunch() {
        XCTAssertFalse(InsightsAccessPolicy.isLocked(status: .unknown, isWalkthroughActive: false))
    }
}
