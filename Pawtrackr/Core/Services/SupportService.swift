import Foundation
import SwiftData
import OSLog

/// Utility to gather system-wide diagnostics for technical support.
final class SupportService {
    static let shared = SupportService()
    
    struct DiagnosticReport: Identifiable {
        let id = UUID()
        let content: String
        let date: Date = Date()
        
        var filename: String {
            "Pawtrackr_Support_Report_\(date.timeIntervalSince1970).txt"
        }
    }
    
    @MainActor
    func generateReport(context: ModelContext) async -> DiagnosticReport {
        var report = "PAWTRACKR SUPPORT DIAGNOSTIC REPORT\n"
        report += "Date: \(Date().formatted())\n"
        report += "App Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "Unknown")\n"
        let deviceName = UserDefaults.standard.string(forKey: AppSettingsKeys.deviceName) ?? ""
        report += "Device Name: \(SupportReportSanitizer.redacted(deviceName))\n"
        report += "Device Token: \(SupportReportSanitizer.deviceToken(for: DeviceIdentity.currentID.uuidString))\n"
        report += "----------------------------------\n\n"
        
        // 1. Data Stats
        report += "STORE STATISTICS:\n"
        report += "- Clients: \(describeCount(try context.fetchCount(FetchDescriptor<Client>())))\n"
        report += "- Pets: \(describeCount(try context.fetchCount(FetchDescriptor<Pet>())))\n"
        report += "- Visits: \(describeCount(try context.fetchCount(FetchDescriptor<Visit>())))\n"
        report += "- Payments: \(describeCount(try context.fetchCount(FetchDescriptor<Payment>())))\n"
        report += "- Checkout Transactions: \(describeCount(try context.fetchCount(FetchDescriptor<CheckoutTransaction>())))\n"
        report += "- Day Summaries: \(describeCount(try context.fetchCount(FetchDescriptor<DaySummary>())))\n\n"
        
        // 2. Local persistence
        report += "STORAGE:\n"
        report += "- Mode: Local device storage\n"
        report += "- Recovery warning: \(UserDefaults.standard.bool(forKey: DataSafetyMonitor.suspectedDataLossKey))\n\n"

        // 3. System Environment
        report += "ENVIRONMENT:\n"
        report += "- Scenario: \(AppRuntime.currentScenario.rawValue)\n"
        report += "- Low Power Mode: \(ProcessInfo.processInfo.isLowPowerModeEnabled)\n\n"
        
        return DiagnosticReport(content: report)
    }

    private func describeCount(_ block: @autoclosure () throws -> Int) -> String {
        do {
            return String(try block())
        } catch {
            return "<error: \(SupportReportSanitizer.redacted(error.localizedDescription))>"
        }
    }
}

enum SupportReportSanitizer {
    /// Redacts common personal data from diagnostic strings before they leave the app.
    static func redacted(_ value: String) -> String {
        var redacted = value
        redacted = replacing(
            pattern: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
            in: redacted,
            with: "<email>",
            options: [.caseInsensitive]
        )
        redacted = replacing(
            pattern: #"(?:file://)?/Users/[^\s]+"#,
            in: redacted,
            with: "<path>"
        )
        redacted = replacing(
            pattern: #"(?<![A-Za-z0-9])(?:\+?1[\s.-]?)?(?:\(?\d{3}\)?[\s.-]?\d{3}[\s.-]?\d{4}|\d{7,})(?![A-Za-z0-9])"#,
            in: redacted,
            with: "<phone>"
        )
        return redacted
    }

    /// Returns a deterministic support token without exposing the raw per-install identifier.
    static func deviceToken(for value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.lowercased().utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16, uppercase: false)
    }

    private static func replacing(
        pattern: String,
        in value: String,
        with replacement: String,
        options: NSRegularExpression.Options = []
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return value
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.stringByReplacingMatches(in: value, options: [], range: range, withTemplate: replacement)
    }
}
