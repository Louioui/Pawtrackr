import Foundation
import SwiftData

@MainActor
class DataSeeder {
    // The single source of truth for all services that should exist in the app.
    private static let allKnownServices: [Service] = [
        // Packages
        Service.fullPackage,
        Service.basicPackage,
        Service.spaPackage,
        // Main Services
        Service.bath,
        Service.haircut,
        // Add-Ons
        Service.deshedding,
        Service.analGlands,
        Service.faceGrooming,
        Service.pawTrim,
        Service.hygieneTrim,
        Service.knotsFee,
        Service.fleaAndTick,
        Service.hairDye
    ]

    /// Synchronizes the services in the database with the `allKnownServices` source of truth.
    /// It adds missing services, deletes obsolete ones, and updates existing ones if their properties have changed.
    static func seedServicesIfNeeded(in context: ModelContext) {
        do {
            let existingServices = try context.fetch(FetchDescriptor<Service>())
            var existingServiceMap = [String: Service]()
            for service in existingServices {
                existingServiceMap[service.name] = service
            }

            var desiredServiceNames = Set<String>()

            // Update existing services and add new ones
            for desiredService in allKnownServices {
                desiredServiceNames.insert(desiredService.name)
                if let existing = existingServiceMap[desiredService.name] {
                    // Service exists, check if it needs an update
                    if existing.category != desiredService.category ||
                       existing.systemIcon != desiredService.systemIcon ||
                       existing.isPackage != desiredService.isPackage
                    {
                        existing.category = desiredService.category
                        existing.systemIcon = desiredService.systemIcon
                        existing.isPackage = desiredService.isPackage
                    }
                } else {
                    // Service does not exist, insert it
                    context.insert(desiredService)
                }
            }

            // Delete old services that are no longer in the desired list
            for existing in existingServices {
                if !desiredServiceNames.contains(existing.name) {
                    context.delete(existing)
                }
            }

            // Save changes if any were made
            if context.hasChanges {
                try context.save()
                print("Successfully synchronized services.")
            }
        } catch {
            // Handle the error appropriately
            print("Failed to synchronize services: \(error)")
        }
    }
}
