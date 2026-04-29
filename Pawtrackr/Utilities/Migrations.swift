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
            EmergencyContact.self,
            BusinessConfig.self,
            MessageTemplate.self
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
            let sortDescriptors = [SortDescriptor(\Pet.createdAt, order: .forward)]
            let batchSize = 500
            var offset = 0
            var updates = 0

            while true {
                var descriptor = FetchDescriptor<Pet>(sortBy: sortDescriptors)
                descriptor.fetchLimit = batchSize
                descriptor.fetchOffset = offset

                let pets = try context.fetch(descriptor)
                if pets.isEmpty { break }

                var batchChanged = false
                for pet in pets {
                    var changed = false
                    // Species is already constrained to .dog/.cat at type level now.
                    // Gender: ensure either .male or .female. If not, default to .male.
                    if pet.gender != .male && pet.gender != .female {
                        pet.gender = .male
                        changed = true
                    }

                    if changed { updates += 1; batchChanged = true }
                }

                if batchChanged {
                    try context.save()
                }

                offset += pets.count
            }

            if updates > 0 {
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

    /// Ensure the service catalog exists with the current set of packages/add-ons,
    /// and strip any default prices so checkout amounts are always user-entered.
    static func ensureServiceCatalog(in context: ModelContext) {
        struct ServiceDefinition {
            let name: String
            let category: Service.Category?
            let icon: String?
            let isPackage: Bool
        }

        let desired: [ServiceDefinition] = [
            // Core packages / services (no default price)
            .init(name: "Full Package",  category: .package, icon: "sparkles", isPackage: true),
            .init(name: "Basic Package", category: .package, icon: "archivebox.fill", isPackage: true),
            .init(name: "Spa Package",   category: .package, icon: "leaf.fill", isPackage: true),
            .init(name: "Bath",          category: .groom,   icon: "shower.fill", isPackage: false),
            .init(name: "Haircut",       category: .groom,   icon: "scissors", isPackage: false),

            // Add-ons (no default price)
            .init(name: "De-shedding",               category: .addOn, icon: "line.3.crossed.swirl.circle.fill", isPackage: false),
            .init(name: "Anal Glands Expression",    category: .addOn, icon: "dot.circle", isPackage: false),
            .init(name: "Face Grooming",             category: .addOn, icon: "mustache.fill", isPackage: false),
            .init(name: "Paw Trim",                  category: .addOn, icon: "pawprint.fill", isPackage: false),
            .init(name: "Hygiene Area Trim",         category: .addOn, icon: "person.fill.viewfinder", isPackage: false),
            .init(name: "Knots and Matting Fee",     category: .addOn, icon: "exclamationmark.triangle.fill", isPackage: false),
            .init(name: "Flea & Ticks Treatment",    category: .addOn, icon: "ladybug.fill", isPackage: false),
            .init(name: "Hair Dye",                  category: .addOn, icon: "paintpalette.fill", isPackage: false)
        ]

        do {
            let existing = try context.fetch(FetchDescriptor<Service>())
            var byName: [String: Service] = [:]
            existing.forEach { byName[$0.name.lowercased()] = $0 }

            for def in desired {
                let key = def.name.lowercased()
                if let svc = byName[key] {
                    // Normalize attributes and remove any default price.
                    svc.setCategory(def.category)
                    svc.setSystemIcon(def.icon)
                    svc.setBasePrice(nil)
                    svc.setEnabled(true)
                    svc.isPackage = def.isPackage
                } else {
                    let svc = Service(
                        name: def.name,
                        category: def.category,
                        systemIcon: def.icon,
                        basePrice: nil,
                        isEnabled: true,
                        isPackage: def.isPackage
                    )
                    context.insert(svc)
                }
            }

            // Persist any updates/inserts.
            if context.hasChanges {
                try context.save()
            }
        } catch {
            Logger.migrations.error("ensureServiceCatalog failed: \(String(describing: error))")
        }
    }

    static func ensureMessageTemplates(in context: ModelContext) {
        do {
            let existing = try context.fetch(FetchDescriptor<MessageTemplate>())
            if existing.isEmpty {
                for template in MessageTemplate.defaults {
                    context.insert(template)
                }
                try context.save()
            }
        } catch {
            Logger.migrations.error("ensureMessageTemplates failed: \(String(describing: error))")
        }
    }
}

extension Logger {
    static let migrations = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "migrations")
}
