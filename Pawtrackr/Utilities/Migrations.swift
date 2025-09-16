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
        [Client.self, Pet.self, Visit.self, VisitItem.self, Service.self, Payment.self, DaySummary.self]
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

    /// Seed a default set of Services if the catalog is empty (or missing key entries).
    /// This provides Grooming Packages and common Individual Services so Checkout has data.
    static func seedServicesIfNeeded(in context: ModelContext) {
        do {
            let existing = try context.fetch(FetchDescriptor<Service>())
            let names = Set(existing.map { $0.name.lowercased() })

            func ensure(_ service: Service) {
                if !names.contains(service.name.lowercased()) {
                    context.insert(service)
                }
            }

            if existing.isEmpty {
                // Grooming Packages
                ensure(Service(name: "Full Grooming Package",  category: .groom, systemIcon: "scissors",           basePrice: 75, defaultDurationMinutes: 120, isEnabled: true))
                ensure(Service(name: "Basic Grooming Package", category: .groom, systemIcon: "sparkles",          basePrice: 65, defaultDurationMinutes: 90,  isEnabled: true))
                ensure(Service(name: "SPA Bath Package",       category: .groom, systemIcon: "shower.fill",       basePrice: 55, defaultDurationMinutes: 75,  isEnabled: true))

                // Individual Services (non-groom)
                ensure(Service(name: "Bath Only",        category: .care,  systemIcon: "drop.fill",            basePrice: 40, defaultDurationMinutes: 45))
                ensure(Service(name: "Haircut",          category: .care,  systemIcon: "scissors",             basePrice: 40, defaultDurationMinutes: 45))
                ensure(Service(name: "De-shedding",      category: .care,  systemIcon: "wind",                 basePrice: 20, defaultDurationMinutes: 15))
                ensure(Service(name: "Anal Glands",      category: .addOn, systemIcon: "circle.fill",          basePrice: 10, defaultDurationMinutes: 10))
                ensure(Service(name: "Nail Clipping",    category: .addOn, systemIcon: "hand.raised.fill",     basePrice: 20, defaultDurationMinutes: 10))
                ensure(Service(name: "Ear Cleaning",     category: .addOn, systemIcon: "ear.and.waveform",     basePrice: 10, defaultDurationMinutes: 10))
                ensure(Service(name: "Face Grooming",    category: .addOn, systemIcon: "person.circle",        basePrice: 12, defaultDurationMinutes: 10))
                ensure(Service(name: "Paw Pad Trim",     category: .addOn, systemIcon: "pawprint",             basePrice: 6,  defaultDurationMinutes: 5))
                ensure(Service(name: "Hygiene Trim",     category: .addOn, systemIcon: "scissors",             basePrice: 9,  defaultDurationMinutes: 8))
                ensure(Service(name: "Teeth Brushing",   category: .addOn, systemIcon: "mouth.fill",           basePrice: 9,  defaultDurationMinutes: 8))

                try context.save()
                Logger.migrations.info("Seeded default Service catalog (packages + individual services).")
            } else {
                // Backfill missing key entries without disturbing existing catalog
                let wanted: [Service] = [
                    Service(name: "Full Grooming Package",  category: .groom, systemIcon: "scissors",       basePrice: 75, defaultDurationMinutes: 120),
                    Service(name: "Basic Grooming Package", category: .groom, systemIcon: "sparkles",      basePrice: 65, defaultDurationMinutes: 90),
                    Service(name: "SPA Bath Package",       category: .groom, systemIcon: "shower.fill",   basePrice: 55, defaultDurationMinutes: 75),
                ]
                var inserted = 0
                for s in wanted where !names.contains(s.name.lowercased()) {
                    context.insert(s); inserted += 1
                }
                if inserted > 0 { try context.save(); Logger.migrations.info("Backfilled \(inserted) package services.") }
            }
        } catch {
            Logger.migrations.error("Service seeding failed: \(String(describing: error))")
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