import Foundation
import SwiftData

/// Utility to generate a "Perfect" business state for App Store marketing.
enum ScreenshotSeeder {
    @MainActor
    static func seedMarketingData(in context: ModelContext) throws {
        // 1. Clear existing
        let clients = try context.fetch(FetchDescriptor<Client>())
        for c in clients { context.delete(c) }
        
        // 2. Add Branded Business
        let config = BusinessConfig(name: "Elite Paws Boutique")
        config.brandAccentColorHex = "#764ba2"
        context.insert(config)
        
        // 3. Add High-Value Clients
        let names = [
            ("Sarah", "Johnson"), ("Michael", "Chen"), ("Emma", "Davis"), 
            ("Robert", "Wilson"), ("Olivia", "Taylor")
        ]
        
        for (first, last) in names {
            let client = Client(firstName: first, lastName: last, phone: "555-01\(Int.random(in: 10...99))")
            context.insert(client)
            
            let petName = ["Cooper", "Bella", "Charlie", "Luna", "Max"].randomElement()!
            let pet = Pet(name: petName, species: .dog)
            pet.setBreed(["Golden Retriever", "Poodle", "French Bulldog", "Beagle"].randomElement()!)
            pet.owner = client
            context.insert(pet)
            
            // Add a few historical visits to populate charts
            for dayOffset in [2, 10, 25, 45] {
                let date = Calendar.current.date(byAdding: .day, value: -dayOffset, to: Date())!
                let visit = Visit(pet: pet, startedAt: date.addingTimeInterval(-3600))
                visit.markCheckedOut(total: Decimal(Int.random(in: 65...120)), now: date)
                context.insert(visit)
                SummaryUpdater.rebuildDay(for: date, in: context)
            }
        }
        
        try context.save()
    }
}
