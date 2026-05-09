//
//  PerformanceMonitor.swift
//  Pawtrackr
//
//  Lightweight instrumentation for measuring operation latency.
//

import Foundation
import OSLog
import QuartzCore

struct PerformanceMonitor {
    private static let log = Logger(subsystem: "com.pawtrackr", category: "Performance")
    
    static func measure<T>(label: String, operation: () -> T) -> T {
        let start = CACurrentMediaTime()
        let result = operation()
        let end = CACurrentMediaTime()
        let duration = (end - start) * 1000
        
        if duration > 100 {
            log.warning("\(label, privacy: .public) took \(duration, format: .fixed(precision: 2))ms")
        } else {
            log.info("\(label, privacy: .public) took \(duration, format: .fixed(precision: 2))ms")
        }
        
        return result
    }
    
    static func measureAsync<T>(label: String, operation: () async throws -> T) async throws -> T {
        let start = CACurrentMediaTime()
        let result = try await operation()
        let end = CACurrentMediaTime()
        let duration = (end - start) * 1000
        
        if duration > 100 {
            log.warning("\(label, privacy: .public) took \(duration, format: .fixed(precision: 2))ms")
        } else {
            log.info("\(label, privacy: .public) took \(duration, format: .fixed(precision: 2))ms")
        }
        
        return result
    }
}
