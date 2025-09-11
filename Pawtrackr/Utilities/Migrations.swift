//
//  Migrations.swift
//  Pawtrackr
//
//  One-time, best-effort data coercions for narrowed enums.
//

import Foundation
import SwiftData
import OSLog

enum DataMigrations {
    static func coercePets(in context: ModelContext) {
        do {
            let pets = try context.fetch(FetchDescriptor<Pet>())
            var updates = 0
            for pet in pets {
                var changed = false
                // Species is already constrained to .dog/.cat at type level now.
                // If older data somehow loads with an unexpected value, leave as-is; SwiftData
                // would typically reject unknown enum cases at decode time.

                // Gender: ensure either .male or .female. If not, default to .male.
                if pet.gender != .male && pet.gender != .female {
                    pet.gender = .male
                    changed = true
                }

                if changed { updates += 1 }
            }
            if updates > 0 {
                try context.save()
                Logger.migrations.info("Coerced \(updates) pet records for narrowed enums.")
            }
        } catch {
            Logger.migrations.error("Migration failed: \(String(describing: error))")
        }
    }
}

extension Logger {
    static let migrations = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "migrations")
}

