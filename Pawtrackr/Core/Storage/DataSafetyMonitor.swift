//
//  DataSafetyMonitor.swift
//  Pawtrackr
//
//  Lightweight protection against app-update data visibility regressions.
//

import Foundation
import SwiftData
import OSLog

enum DataSafetyMonitor {
    static let suspectedDataLossKey = "pawtrackr.dataSafety.suspectedDataLoss"
    static let suspectedDataLossMessageKey = "pawtrackr.dataSafety.suspectedDataLossMessage"
    static let suspectedDataLossRecoveryDetailKey = "pawtrackr.dataSafety.recoveryDetail"
    static let lastKnownClientCountKey = "pawtrackr.dataSafety.lastKnownClientCount"
    static let lastKnownClientCountBuildKey = "pawtrackr.dataSafety.lastKnownClientCountBuild"

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "DataSafety")

    static var isDataLossSuspected: Bool {
        UserDefaults.standard.bool(forKey: suspectedDataLossKey)
    }

    static func evaluateClientStoreState(
        in context: ModelContext,
        appSupportURL overrideAppSupportURL: URL? = nil,
        userDefaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        do {
            // Sample clients (fixed UUIDs, `SampleData`) are practice rows, so
            // they never count. Otherwise loading them would raise the baseline
            // and removing them, on this device or through iCloud on another,
            // would read as "had 2 clients, now none" and lock Start Fresh. A
            // store holding only samples is empty of real clients.
            var uuidDescriptor = FetchDescriptor<Client>()
            uuidDescriptor.propertiesToFetch = [\.uuid]
            let realClientUUIDs = try context.fetch(uuidDescriptor).map(\.uuid).filter { !SampleData.clientIDs.contains($0) }
            let currentCount = realClientUUIDs.count
            let lastKnownCount = userDefaults.integer(forKey: lastKnownClientCountKey)

            // Offer on-device backups on their own evidence: 1.0.1 and 1.0.2
            // never wrote lastKnownClientCount, so users who lost clients to the
            // 1.0.2 recovery screen read 0 here. Only clients missing from this
            // store count, so data iCloud already brought back isn't offered.
            let liveClientUUIDs = Set(realClientUUIDs)
            StoreBackupRestore.publishOffer(
                liveClientUUIDs: liveClientUUIDs,
                appSupportURL: overrideAppSupportURL,
                userDefaults: userDefaults,
                fileManager: fileManager
            )

            // Only an empty store is evidence of loss. Counts also drop for
            // ordinary reasons (a deleted client, a sync still importing), and
            // flagging those locked Start Fresh behind a banner that never cleared.
            guard currentCount == 0, lastKnownCount > 0 else {
                recordHealthyClientCount(currentCount, userDefaults: userDefaults)
                return
            }

            recordSuspectedDataLoss(
                previousCount: lastKnownCount,
                candidate: findRecoveryCandidate(appSupportURL: overrideAppSupportURL, fileManager: fileManager),
                userDefaults: userDefaults
            )
        } catch {
            log.error("Client store safety evaluation failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func recordHealthyClientCount(_ count: Int, userDefaults: UserDefaults = .standard) {
        userDefaults.set(max(0, count), forKey: lastKnownClientCountKey)
        userDefaults.set(appBuildIdentifier, forKey: lastKnownClientCountBuildKey)
        userDefaults.removeObject(forKey: suspectedDataLossKey)
        userDefaults.removeObject(forKey: suspectedDataLossMessageKey)
        userDefaults.removeObject(forKey: suspectedDataLossRecoveryDetailKey)
    }

    static func clearAfterIntentionalWipe() {
        let defaults = UserDefaults.standard
        // Every backup now holds the data the user chose to erase.
        StoreBackupRestore.dismissAllCurrentBackups(userDefaults: defaults)
        defaults.set(0, forKey: lastKnownClientCountKey)
        defaults.set(appBuildIdentifier, forKey: lastKnownClientCountBuildKey)
        defaults.removeObject(forKey: suspectedDataLossKey)
        defaults.removeObject(forKey: suspectedDataLossMessageKey)
        defaults.removeObject(forKey: suspectedDataLossRecoveryDetailKey)
    }

    private static func recordSuspectedDataLoss(
        previousCount: Int,
        candidate: StoreBackupRestore.Candidate?,
        userDefaults: UserDefaults
    ) {
        var message = String(
            format: AppLocalization.localized(
                "data_safety.empty_store_fmt",
                value: "Pawtrackr had %d clients on this device, but opened with none. Don't delete the app or use Start Fresh."
            ),
            previousCount
        )
        if let candidate {
            message += " " + String(
                format: AppLocalization.localized(
                    "data_safety.backup_found_fmt",
                    value: "A backup on this device has %d clients — tap Review to bring them back."
                ),
                candidate.missingClientCount(liveClientUUIDs: [])
            )
            userDefaults.set(candidate.directoryName, forKey: suspectedDataLossRecoveryDetailKey)
        } else {
            userDefaults.removeObject(forKey: suspectedDataLossRecoveryDetailKey)
        }

        userDefaults.set(true, forKey: suspectedDataLossKey)
        userDefaults.set(message, forKey: suspectedDataLossMessageKey)
        log.critical("Data safety anomaly detected: previousClientCount=\(previousCount), currentClientCount=0")
    }

    private static func findRecoveryCandidate(
        appSupportURL overrideAppSupportURL: URL?,
        fileManager: FileManager
    ) -> StoreBackupRestore.Candidate? {
        // Counted without sample clients, like the baseline: a backup that
        // holds only the practice clients has nothing of the user's to offer.
        StoreBackupRestore.candidates(appSupportURL: overrideAppSupportURL, fileManager: fileManager)
            .map { (candidate: $0, realClients: $0.missingClientCount(liveClientUUIDs: [])) }
            .filter { $0.realClients > 0 }
            .max { $0.realClients < $1.realClients }?
            .candidate
    }

    private static var appBuildIdentifier: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info?["CFBundleVersion"] as? String ?? "unknown"
        return "\(version)-\(build)"
    }
}
