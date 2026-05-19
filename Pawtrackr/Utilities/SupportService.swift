import Foundation
import SwiftData
import CloudKit
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
        report += "Device ID: \(DeviceIdentity.currentID.uuidString)\n"
        report += "----------------------------------\n\n"
        
        // 1. Data Stats
        report += "STORE STATISTICS:\n"
        report += "- Clients: \(describeCount(try context.fetchCount(FetchDescriptor<Client>())))\n"
        report += "- Pets: \(describeCount(try context.fetchCount(FetchDescriptor<Pet>())))\n"
        report += "- Visits: \(describeCount(try context.fetchCount(FetchDescriptor<Visit>())))\n"
        report += "- Payments: \(describeCount(try context.fetchCount(FetchDescriptor<Payment>())))\n"
        report += "- Checkout Transactions: \(describeCount(try context.fetchCount(FetchDescriptor<CheckoutTransaction>())))\n"
        report += "- Day Summaries: \(describeCount(try context.fetchCount(FetchDescriptor<DaySummary>())))\n\n"
        
        // 2. iCloud Status
        report += "ICLOUD STATUS:\n"
        let monitor = CloudKitMonitor.shared
        report += "- Account: \(monitor.accountState.displayLabel)\n"
        report += "- Network: \(monitor.networkState.displayLabel)\n"
        report += "- Health: \(monitor.healthHeadline)\n"
        report += "- Detail: \(monitor.healthDetail)\n"
        report += "- First Sync Completed: \(monitor.firstSyncCompleted)\n"
        report += "- Pending Changes: \(monitor.pendingChangesSummary ?? "none")\n"
        report += "- Last Sync: \(monitor.lastSyncDate?.formatted() ?? "never")\n"
        report += "- Last Import: \(monitor.lastImportDate?.formatted() ?? "never")\n"
        report += "- Last Export: \(monitor.lastExportDate?.formatted() ?? "never")\n"
        report += "- Quota Exceeded: \(monitor.quotaExceeded)\n"
        report += "- App Access Warning: \(monitor.iCloudAppAccessMayBeDisabled)\n"
        report += "- Last Error: \(monitor.lastErrorMessage ?? "none")\n"
        report += "- Health Issues:\n"
        if monitor.healthIssues.isEmpty {
            report += "  - none\n"
        } else {
            for issue in monitor.healthIssues {
                report += "  - \(issue.title): \(issue.detail)\n"
            }
        }
        report += "- Recent Sync Events:\n"
        if monitor.syncEvents.isEmpty {
            report += "  - none\n"
        } else {
            for event in monitor.syncEvents {
                let code = event.errorCode.map { " [\($0)]" } ?? ""
                report += "  - \(event.startedAt.formatted()) \(event.kind.displayLabel) \(event.status.displayLabel): \(event.message)\(code)\n"
            }
        }
        report += "\n"
        
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
            return "<error: \(error.localizedDescription)>"
        }
    }
}
