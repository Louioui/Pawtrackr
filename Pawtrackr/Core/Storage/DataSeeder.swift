import Foundation
import SwiftData
import OSLog

private let dataSeederLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "DataSeeder")

@MainActor
class DataSeeder {
    /// Returns the source of truth for all services that should exist in the app.
    private static func makeDesiredServices() -> [Service] {
        DefaultServiceCatalog.definitions.map {
            Service(
                name: $0.localizedName,
                category: $0.category,
                systemIcon: $0.icon,
                isPackage: $0.isPackage
            )
        }
    }

    /// Synchronizes the services in the database with the source of truth.
    /// It adds missing services, deletes obsolete ones, and updates existing ones if their properties have changed.
    static func seedServicesIfNeeded(in context: ModelContext) {
        do {
            let existingServices = try context.fetch(FetchDescriptor<Service>())
            var existingServiceMap = [String: Service]()
            for service in existingServices {
                existingServiceMap[service.name] = service
            }

            let desiredServices = makeDesiredServices()
            var desiredServiceNames = Set<String>()

            // Update existing services and add new ones
            for desiredService in desiredServices {
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
                dataSeederLog.info("Synchronized service catalog.")
            }
        } catch {
            dataSeederLog.error("Failed to synchronize services: \(error.localizedDescription, privacy: .public)")
        }
    }
}
