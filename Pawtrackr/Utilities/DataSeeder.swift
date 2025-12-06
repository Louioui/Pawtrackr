import Foundation
import SwiftData

@MainActor
class DataSeeder {
    static func seedServicesIfNeeded(in context: ModelContext) {
        let descriptor = FetchDescriptor<Service>()
        guard let count = try? context.fetchCount(descriptor), count == 0 else {
            // Data already exists, no seeding needed.
            return
        }

        // Seed the data
        context.insert(Service.bath)
        context.insert(Service.trim)
        context.insert(Service.nails)
        context.insert(Service.ears)
        context.insert(Service.teeth)
        context.insert(Service.deshed)
        context.insert(Service.fullGroom)

        do {
            try context.save()
        } catch {
            // Handle the error appropriately
            print("Failed to save seeded services: \(error)")
        }
    }
}
