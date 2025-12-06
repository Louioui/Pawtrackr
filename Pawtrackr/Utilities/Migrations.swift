//
//  Migrations.swift
//  Pawtrackr
//
//  Schema migration plan and one-time data seeding/coercion.
//

import Foundation
import SwiftData
import OSLog

// MARK: - Schema Migration Plan

enum PawtrackrSchema: VersionedSchema {
    static var versionIdentifier: Schema.Version = .init(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            // Core domain
            Client.self,
            Pet.self,
            Visit.self,
            VisitItem.self,
            Service.self,
            Payment.self,
            Appointment.self,
            User.self,

            // Insights aggregates
            DaySummary.self,
            ServiceDaySummary.self,
            CategoryDaySummary.self,

            // Aux tables
            EmergencyContact.self
        ]
    }
    
    // Define V1 (initial) and V2 (adds lastVisitDate) as needed.
    // For this case, a single schema definition is sufficient as we'll use a lightweight migration.
}


enum PawtrackrMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [PawtrackrSchema.self]
    }

    static var stages: [MigrationStage] {
        // For now, we only have lightweight migrations (adding optional properties).
        // If a more complex migration is needed in the future, we would define a custom stage here.
        []
    }
}


// MARK: - Data Seeding & Coercion

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



    /// Build or refresh DaySummary rows from existing completed visits.
    /// Safe to run multiple times; it re-computes aggregates per distinct day.
    static func backfillDaySummaries(in context: ModelContext) {
        do {
            let completedDesc = FetchDescriptor<Visit>(
                predicate: #Predicate { $0.endedAt != nil },
                sortBy: [SortDescriptor(\.endedAt, order: .forward)]
            )
            let visits = try context.fetch(completedDesc)
            let cal = Calendar.current
            var byDay: [Date: (Decimal, Int)] = [:]
            for v in visits {
                guard let end = v.endedAt else { continue }
                let day = cal.startOfDay(for: end)
                var agg = byDay[day] ?? (.zero, 0)
                agg.0 += v.total
                agg.1 += 1
                byDay[day] = agg
            }

            // Fetch existing summaries to upsert
            let existing = try context.fetch(FetchDescriptor<DaySummary>()) 
            var index: [Date: DaySummary] = [:]
            for s in existing { index[s.day] = s }

            var updated = 0, inserted = 0
            for (day, (rev, cnt)) in byDay {
                if let s = index[day] {
                    if s.revenue != rev || s.visitCount != cnt { s.revenue = rev; s.visitCount = cnt; updated += 1 }
                } else {
                    context.insert(DaySummary(day: day, revenue: rev, visitCount: cnt)); inserted += 1
                }
            }
            if inserted + updated > 0 { try context.save() }
            Logger.migrations.info("DaySummary backfill: inserted=\(inserted), updated=\(updated)")
        } catch {
            Logger.migrations.error("DaySummary backfill failed: \(String(describing: error))")
        }
    }
}

extension Logger {
    static let migrations = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "migrations")
}
