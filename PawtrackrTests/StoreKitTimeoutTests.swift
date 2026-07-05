//
//  StoreKitTimeoutTests.swift
//  PawtrackrTests
//
//  Guards the paywall's bounded product fetch: a hung StoreKit call must
//  surface a retryable error instead of stranding the UI in a loading state.
//

import XCTest
@testable import Pawtrackr

final class StoreKitTimeoutTests: XCTestCase {

    func testReturnsValueWhenOperationCompletesInTime() async throws {
        let value = try await StoreKitTimeout.run(seconds: 1.0) { 42 }
        XCTAssertEqual(value, 42)
    }

    func testThrowsTimedOutWhenOperationHangs() async {
        do {
            _ = try await StoreKitTimeout.run(seconds: 0.05) { () -> Int in
                try await Task.sleep(for: .seconds(10))
                return 1
            }
            XCTFail("Expected StoreKitTimeout.TimedOut")
        } catch is StoreKitTimeout.TimedOut {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testOperationErrorsPropagateUnchanged() async {
        struct Boom: Error, Equatable {}
        do {
            _ = try await StoreKitTimeout.run(seconds: 1.0) { () -> Int in
                throw Boom()
            }
            XCTFail("Expected Boom")
        } catch is Boom {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testHungOperationIsCancelledAfterTimeout() async {
        let cancelled = expectation(description: "operation observed cancellation")
        do {
            _ = try await StoreKitTimeout.run(seconds: 0.05) { () -> Int in
                do {
                    try await Task.sleep(for: .seconds(10))
                } catch {
                    cancelled.fulfill()
                    throw error
                }
                return 1
            }
            XCTFail("Expected StoreKitTimeout.TimedOut")
        } catch is StoreKitTimeout.TimedOut {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        await fulfillment(of: [cancelled], timeout: 2.0)
    }

    func testTimedOutIsUserPresentable() {
        XCTAssertFalse(StoreKitTimeout.TimedOut().localizedDescription.isEmpty)
    }
}
