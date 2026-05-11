import XCTest
import SwiftData
@testable import Pawtrackr

@MainActor
final class LargeDatasetRepositoryTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema(PawtrackrSchema.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [config])
        context = container.mainContext
    }

    override func tearDownWithError() throws {
        container = nil
        context = nil
    }

    func testClientRepository_PaginatesLargeInactiveDatasetAndBoundsActiveFetch() async throws {
        for index in 0..<600 {
            let client = Client(firstName: "Client", lastName: String(format: "%04d", index))
            let pet = Pet(name: "Pet \(index)", species: .dog)
            pet.owner = client
            client.pets = [pet]
            context.insert(client)
            context.insert(pet)

            if index < 5 {
                let visit = Visit(pet: pet, startedAt: .now.addingTimeInterval(TimeInterval(-index * 60)))
                context.insert(visit)
            }
        }
        try context.save()

        let repository = ClientRepository(modelContainer: container)
        let active = try await repository.fetchActiveClients(query: "")
        let inactivePage = try await repository.fetchInactiveClients(query: "", limit: 50, offset: 0)

        XCTAssertEqual(active.count, 5)
        XCTAssertEqual(inactivePage.0.count, 50)
        XCTAssertTrue(inactivePage.1)
        let inactiveClients = inactivePage.0.compactMap { context.model(for: $0) as? Client }
        XCTAssertFalse(inactiveClients.contains(where: \.hasActiveVisit))
    }
}
