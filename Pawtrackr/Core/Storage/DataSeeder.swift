import Foundation
import SwiftData
import OSLog

private let dataSeederLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "DataSeeder")

@MainActor
class DataSeeder {
    /// Returns the source of truth for all services that should exist in the app.
    private static func makeDesiredServices() -> [Service] {
        return [
            // Packages
            Service(name: "Full Package", category: .package, systemIcon: "sparkles", isPackage: true),
            Service(name: "Basic Package", category: .package, systemIcon: "archivebox.fill", isPackage: true),
            Service(name: "Spa Package", category: .package, systemIcon: "leaf.fill", isPackage: true),
            // Main Services
            Service(name: "Bath", category: .groom, systemIcon: "shower.fill"),
            Service(name: "Haircut", category: .groom, systemIcon: "scissors"),
            // Add-Ons
            Service(name: "De-shedding", category: .addOn, systemIcon: "line.3.crossed.swirl.circle.fill"),
            Service(name: "Anal Glands Expression", category: .addOn, systemIcon: "dot.circle"),
            Service(name: "Face Grooming", category: .addOn, systemIcon: "mustache.fill"),
            Service(name: "Paw Trim", category: .addOn, systemIcon: "pawprint.fill"),
            Service(name: "Hygiene Area Trim", category: .addOn, systemIcon: "person.fill.viewfinder"),
            Service(name: "Knots and Matting Fee", category: .addOn, systemIcon: "exclamationmark.triangle.fill"),
            Service(name: "Flea & Ticks Treatment", category: .addOn, systemIcon: "ladybug.fill"),
            Service(name: "Hair Dye", category: .addOn, systemIcon: "paintpalette.fill")
        ]
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
