import XCTest
import CloudKit
@testable import Pawtrackr

final class ResilienceCoordinatorTests: XCTestCase {
    private actor AttemptCounter {
        private(set) var value = 0

        func next() -> Int {
            value += 1
            return value
        }
    }

    private enum TestError: Error, Equatable {
        case terminal
    }

    func testRunRetriesRetryableErrorsUntilSuccess() async throws {
        let attempts = AttemptCounter()
        let policy = RetryPolicy(maxAttempts: 3, baseDelaySeconds: 0, maxDelaySeconds: 0, jitterFactor: 0)

        let result = try await ResilienceCoordinator.run(
            label: "qc-retry-success",
            policy: policy,
            classify: { _ in .retryable }
        ) {
            if await attempts.next() < 3 {
                throw CKError(.networkUnavailable)
            }
            return 42
        }

        XCTAssertEqual(result, 42)
        let finalAttempts = await attempts.value
        XCTAssertEqual(finalAttempts, 3)
    }

    func testRunStopsImmediatelyOnTerminalError() async {
        let attempts = AttemptCounter()
        let policy = RetryPolicy(maxAttempts: 4, baseDelaySeconds: 0, maxDelaySeconds: 0, jitterFactor: 0)

        do {
            _ = try await ResilienceCoordinator.run(
                label: "qc-terminal-stop",
                policy: policy,
                classify: { _ in .terminal }
            ) {
                _ = await attempts.next()
                throw TestError.terminal
            }
            XCTFail("Expected terminal error to be thrown.")
        } catch let error as TestError {
            XCTAssertEqual(error, .terminal)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

        let finalAttempts = await attempts.value
        XCTAssertEqual(finalAttempts, 1)
    }

    func testCloudKitDispositionClassifiesTransientFailures() {
        XCTAssertEqual(ResilienceCoordinator.cloudKitDisposition(for: CKError(.networkFailure)), .retryable)
        XCTAssertEqual(ResilienceCoordinator.cloudKitDisposition(for: CKError(.serviceUnavailable)), .retryable)
        XCTAssertEqual(ResilienceCoordinator.cloudKitDisposition(for: CKError(.badDatabase)), .terminal)
    }
}
