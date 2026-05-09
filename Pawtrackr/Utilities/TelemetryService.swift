//
//  TelemetryService.swift
//  Pawtrackr
//
//  Lightweight, privacy-first analytics event tracker.
//

import Foundation
import OSLog

final class TelemetryService {
    static let shared = TelemetryService()
    private let log = Logger(subsystem: "com.pawtrackr", category: "Telemetry")
    
    private init() {}
    
    func track(event: String, parameters: [String: String] = [:]) {
        // In a real implementation, this would queue events for periodic batch uploading.
        // For now, we log to unified logging which is accessible via Console.app.
        let paramString = parameters.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
        log.info("Telemetry Event: \(event, privacy: .public) | \(paramString, privacy: .public)")
    }
}
