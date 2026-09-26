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
            let currentCount = try context.fetchCount(FetchDescriptor<Client>())
            let lastKnownCount = userDefaults.integer(forKey: lastKnownClientCountKey)

            if currentCount > 0 {
                if lastKnownCount > currentCount {
                    let candidate = findRecoveryCandidate(appSupportURL: overrideAppSupportURL, fileManager: fileManager)
                    if let candidate, candidate.clientCount > currentCount {
                        recordSuspectedDataLoss(
                            previousCount: lastKnownCount,
                            currentCount: currentCount,
                            candidate: candidate,
                            userDefaults: userDefaults
                        )
                        return
                    }
                }

                recordHealthyClientCount(currentCount, userDefaults: userDefaults)
                return
            }

            guard lastKnownCount > 0 else {
                userDefaults.set(0, forKey: lastKnownClientCountKey)
                userDefaults.set(appBuildIdentifier, forKey: lastKnownClientCountBuildKey)
                return
            }

            recordSuspectedDataLoss(
                previousCount: lastKnownCount,
                currentCount: currentCount,
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
        defaults.set(0, forKey: lastKnownClientCountKey)
        defaults.set(appBuildIdentifier, forKey: lastKnownClientCountBuildKey)
        defaults.removeObject(forKey: suspectedDataLossKey)
        defaults.removeObject(forKey: suspectedDataLossMessageKey)
        defaults.removeObject(forKey: suspectedDataLossRecoveryDetailKey)
    }

    private static func recordSuspectedDataLoss(
        previousCount: Int,
        currentCount: Int,
        candidate: RecoveryCandidate?,
        userDefaults: UserDefaults
    ) {
        let openedStoreDescription: String
        if currentCount == 0 {
            openedStoreDescription = "an empty client store"
        } else {
            openedStoreDescription = "only \(currentCount) client\(currentCount == 1 ? "" : "s")"
        }
        let message: String

        if let candidate {
            message = "Pawtrackr previously saw \(previousCount) client\(previousCount == 1 ? "" : "s"), but this launch opened \(openedStoreDescription). A local backup or legacy store may contain \(candidate.clientCount) client\(candidate.clientCount == 1 ? "" : "s")."
            userDefaults.set("\(candidate.clientCount) client row(s) found in \(candidate.relativePath)", forKey: suspectedDataLossRecoveryDetailKey)
        } else {
            message = "Pawtrackr previously saw \(previousCount) client\(previousCount == 1 ? "" : "s"), but this launch opened \(openedStoreDescription). Avoid deleting the app or using Start Fresh until the store is checked."
            userDefaults.removeObject(forKey: suspectedDataLossRecoveryDetailKey)
        }

        userDefaults.set(true, forKey: suspectedDataLossKey)
        userDefaults.set(message, forKey: suspectedDataLossMessageKey)
        log.critical("Data safety anomaly detected: previousClientCount=\(previousCount), currentClientCount=\(currentCount)")
    }

    private static func findRecoveryCandidate(appSupportURL overrideAppSupportURL: URL?, fileManager: FileManager) -> RecoveryCandidate? {
        guard let appSupportURL = overrideAppSupportURL ?? (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )) else {
            return nil
        }

        let candidates = storeCandidateURLs(in: appSupportURL, fileManager: fileManager)
        return candidates
            .compactMap { url -> RecoveryCandidate? in
                guard let count = StoreFileMigration.clientRowCount(in: url), count > 0 else { return nil }
                return RecoveryCandidate(clientCount: count, relativePath: relativePath(for: url, root: appSupportURL))
            }
            .max { first, second in
                first.clientCount < second.clientCount
            }
    }

    private static func storeCandidateURLs(in appSupportURL: URL, fileManager: FileManager) -> [URL] {
        var urls: [URL] = []
        let directNames = ["default.store", "Pawtrackr.store"]
        for name in directNames {
            let url = appSupportURL.appendingPathComponent(name)
            if fileManager.fileExists(atPath: url.path) {
                urls.append(url)
            }
        }

        guard let topLevel = try? fileManager.contentsOfDirectory(
            at: appSupportURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else {
            return urls
        }

        for directory in topLevel where isBackupDirectory(directory) {
            for name in directNames {
                let url = directory.appendingPathComponent(name)
                if fileManager.fileExists(atPath: url.path) {
                    urls.append(url)
                }
            }
        }

        return urls
    }

    private static func isBackupDirectory(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        return name.hasPrefix("PreMigrationBackup-")
            || name.hasPrefix("StoreMigrationBackup-")
            || name.hasPrefix("RecoveryBackup-")
    }

    private static func relativePath(for url: URL, root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath) else { return url.lastPathComponent }
        return String(path.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static var appBuildIdentifier: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info?["CFBundleVersion"] as? String ?? "unknown"
        return "\(version)-\(build)"
    }

    private struct RecoveryCandidate {
        let clientCount: Int
        let relativePath: String
    }
}
