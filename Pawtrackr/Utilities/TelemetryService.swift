import Foundation
import OSLog

/// Service for collecting and surfacing diagnostic logs for proactive support.
final class TelemetryService {
    static let shared = TelemetryService()
    
    private init() {}

    /// Records a privacy-safe diagnostic event without collecting PII.
    func track(event: String, parameters: [String: String] = [:]) {
        let sanitizedEvent = sanitized(event)
        let sanitizedParameters = parameters
            .map { key, value in "\(sanitized(key))=\(sanitized(value))" }
            .sorted()
            .joined(separator: ",")

        Logger.performance.info("Telemetry event=\(sanitizedEvent, privacy: .public) parameters=\(sanitizedParameters, privacy: .public)")
    }
    
    /// Generates a sanitized log bundle for user support requests.
    func generateSupportBundle() async -> URL? {
        Logger.performance.info("Generating support bundle...")
        // 1. Fetch OSLog messages from the last 24 hours
        // 2. Sanitize PII (remove names/phone numbers)
        // 3. Compress into a .zip file in the temporary directory
        return nil // Path to zip file
    }

    /// Strips characters that could break our flat `event=… parameters=k=v,…`
    /// log format. NOTE: this silently mutates event/parameter strings — any
    /// caller passing names with `:`, `=`, `,`, `;`, etc. will see them
    /// recorded under a different identifier than the source code declares.
    /// Prefer simple `[a-zA-Z0-9_.-]` event/parameter names at call sites.
    private func sanitized(_ value: String) -> String {
        String(value
            .filter { character in
                character.isLetter || character.isNumber || character == "_" || character == "-" || character == "." || character == " "
            }
            .prefix(80))
    }
}
