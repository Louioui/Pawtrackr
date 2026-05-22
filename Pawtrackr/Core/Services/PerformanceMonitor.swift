//
//  PerformanceMonitor.swift
//  Pawtrackr
//
//  Lightweight instrumentation for measuring operation latency.
//  Emits both Logger entries (visible in Console.app) and OSSignposter
//  intervals (visible in Instruments → Time Profiler "Points of Interest"
//  track) so we can see app-defined work alongside CPU samples.
//

import Foundation
import OSLog
import QuartzCore

struct PerformanceMonitor {
    private static let log = Logger(subsystem: "com.pawtrackr", category: "Performance")
    private static let signposter = OSSignposter(subsystem: "com.pawtrackr", category: "Performance")

    /// Static name used for every interval the signposter emits. Instruments
    /// groups by this name; the dynamic per-call label is passed as the
    /// signpost message so it's still distinguishable in the timeline.
    private static let intervalName: StaticString = "Operation"

    static func measure<T>(label: String, operation: () -> T) -> T {
        let signpostID = signposter.makeSignpostID()
        let state = signposter.beginInterval(intervalName, id: signpostID, "\(label, privacy: .public)")
        let start = CACurrentMediaTime()
        defer {
            let end = CACurrentMediaTime()
            let duration = (end - start) * 1000
            signposter.endInterval(intervalName, state)
            logDuration(label: label, ms: duration)
        }
        return operation()
    }

    static func measureAsync<T>(label: String, operation: () async throws -> T) async throws -> T {
        let signpostID = signposter.makeSignpostID()
        let state = signposter.beginInterval(intervalName, id: signpostID, "\(label, privacy: .public)")
        let start = CACurrentMediaTime()
        do {
            let result = try await operation()
            let end = CACurrentMediaTime()
            let duration = (end - start) * 1000
            signposter.endInterval(intervalName, state)
            logDuration(label: label, ms: duration)
            return result
        } catch {
            signposter.endInterval(intervalName, state, "error: \(label, privacy: .public)")
            throw error
        }
    }

    /// Non-throwing async variant — most critical paths in this app are
    /// declared `async` (no `throws`). Calling `measureAsync` on them
    /// previously required a `try` even though no error was possible.
    static func measureAsyncNoThrow<T>(label: String, operation: () async -> T) async -> T {
        let signpostID = signposter.makeSignpostID()
        let state = signposter.beginInterval(intervalName, id: signpostID, "\(label, privacy: .public)")
        let start = CACurrentMediaTime()
        let result = await operation()
        let end = CACurrentMediaTime()
        let duration = (end - start) * 1000
        signposter.endInterval(intervalName, state)
        logDuration(label: label, ms: duration)
        return result
    }

    private static func logDuration(label: String, ms: Double) {
        if ms > 100 {
            log.warning("\(label, privacy: .public) took \(ms, format: .fixed(precision: 2))ms")
        } else {
            log.info("\(label, privacy: .public) took \(ms, format: .fixed(precision: 2))ms")
        }
    }
}
