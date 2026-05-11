//
//  ResilienceCoordinator.swift
//  Pawtrackr
//
//  Lightweight retry coordination for transient network and store conditions.
//

import Foundation
import CloudKit
import CoreData
import OSLog

struct RetryPolicy: Sendable {
    let maxAttempts: Int
    let baseDelaySeconds: Double
    let maxDelaySeconds: Double
    let jitterFactor: Double

    static let cloudKit = RetryPolicy(
        maxAttempts: 3,
        baseDelaySeconds: 0.25,
        maxDelaySeconds: 2.0,
        jitterFactor: 0.18
    )

    static let dataIntegrity = RetryPolicy(
        maxAttempts: 2,
        baseDelaySeconds: 0.10,
        maxDelaySeconds: 0.35,
        jitterFactor: 0.0
    )

    fileprivate func sleepNanoseconds(for attempt: Int) -> UInt64 {
        let exponent = max(0, attempt - 1)
        let scaledDelay = min(maxDelaySeconds, baseDelaySeconds * pow(2.0, Double(exponent)))
        let jitterScale = 1 + Double.random(in: -jitterFactor...jitterFactor)
        let jitteredDelay = max(0, scaledDelay * jitterScale)
        return UInt64(jitteredDelay * 1_000_000_000)
    }
}

enum RetryDisposition: Sendable, Equatable {
    case retryable
    case terminal
}

struct ResilienceCoordinator {
    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr",
        category: "Resilience"
    )

    static func run<T>(
        label: String,
        policy: RetryPolicy,
        classify: (Error) -> RetryDisposition,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        var lastError: Error?

        for attempt in 1...policy.maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error
                let disposition = classify(error)
                guard disposition == .retryable, attempt < policy.maxAttempts else {
                    throw error
                }

                let delay = policy.sleepNanoseconds(for: attempt)
                let milliseconds = Double(delay) / 1_000_000
                log.warning(
                    "\(label, privacy: .public) attempt \(attempt) failed; retrying in \(milliseconds, format: .fixed(precision: 0))ms"
                )
                try? await Task.sleep(nanoseconds: delay)
            }
        }

        throw lastError ?? AppError.unknown("Retry operation failed without an error payload.")
    }

    static func cloudKitDisposition(for error: Error) -> RetryDisposition {
        guard let ckError = ckError(from: error) else { return .terminal }

        switch ckError.code {
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy, .partialFailure:
            return .retryable
        default:
            return .terminal
        }
    }

    private static func ckError(from error: Error) -> CKError? {
        if let ckError = error as? CKError {
            return ckError
        }

        let nsError = error as NSError
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return ckError(from: underlying)
        }
        if let detailed = nsError.userInfo[NSDetailedErrorsKey] as? [Error] {
            return detailed.compactMap(ckError(from:)).first
        }
        return nil
    }
}
