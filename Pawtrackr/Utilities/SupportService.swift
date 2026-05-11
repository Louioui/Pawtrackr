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
        let clientCount = (try? context.fetchCount(FetchDescriptor<Client>())) ?? -1
        let petCount = (try? context.fetchCount(FetchDescriptor<Pet>())) ?? -1
        let visitCount = (try? context.fetchCount(FetchDescriptor<Visit>())) ?? -1
        report += "- Clients: \(clientCount)\n"
        report += "- Pets: \(petCount)\n"
        report += "- Visits: \(visitCount)\n\n"
        
        // 2. iCloud Status
        report += "ICLOUD STATUS:\n"
        let status = CloudKitMonitor.shared.accountState
        report += "- State: \(String(describing: status))\n"
        report += "- Sync Completed: \(CloudKitMonitor.shared.firstSyncCompleted)\n\n"
        
        // 3. System Environment
        report += "ENVIRONMENT:\n"
        report += "- Scenario: \(AppRuntime.currentScenario.rawValue)\n"
        report += "- Low Power Mode: \(ProcessInfo.processInfo.isLowPowerModeEnabled)\n\n"
        
        return DiagnosticReport(content: report)
    }
}
