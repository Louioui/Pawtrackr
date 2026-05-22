//
//  DataPruningService.swift
//  Pawtrackr
//
//  Automated janitorial service for maintaining storage health.
//

import Foundation
import OSLog

final class DataPruningService {
    static let shared = DataPruningService()
    
    private init() {}
    
    /// Clears temporary assets older than 30 days.
    func performMaintenance() {
        Logger.performance.info("Starting automated data pruning.")
        let fm = FileManager.default
        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        
        let paths = [
            fm.temporaryDirectory.appendingPathComponent("PDFReceipts"),
            fm.temporaryDirectory.appendingPathComponent("Thumbnails")
        ]
        
        for folder in paths {
            guard fm.fileExists(atPath: folder.path) else { continue }
            do {
                let contents = try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])
                for file in contents {
                    let attr = try fm.attributesOfItem(atPath: file.path)
                    if let modDate = attr[.modificationDate] as? Date, modDate < thirtyDaysAgo {
                        try fm.removeItem(at: file)
                        Logger.performance.debug("Pruned stale asset: \(file.lastPathComponent)")
                    }
                }
            } catch {
                Logger.performance.error("Pruning failed for folder \(folder.lastPathComponent): \(error.localizedDescription)")
            }
        }
        Logger.performance.info("Completed automated data pruning.")
    }
}
