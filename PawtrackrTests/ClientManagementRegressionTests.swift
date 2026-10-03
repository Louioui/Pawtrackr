import XCTest
import SwiftData
@testable import Pawtrackr

@MainActor
final class ClientManagementRegressionTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema(PawtrackrSchema.models)
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        context = container.mainContext
    }

    private func seedClient() throws -> (Client, Pet) {
        let client = Client(firstName: "Érika", lastName: "Álvarado", phone: "+13235550123", email: "erika@example.com")
        let pet = Pet(name: "Muñeca", species: .dog)
        pet.breed = "Golden Retriever"
        context.insert(client)
        context.insert(pet)
        pet.owner = client
        try context.save()
        return (client, pet)
    }

    func testTokensMatchAcrossFieldsInAnyOrderAndRequireEveryToken() throws {
        let (client, _) = try seedClient()
        for query in ["erika alvarado", "alvarado ERIKA", "erika muneca", "retriever erika", "muneca 0123", "  ERIKA\n golden  ", "email:erika@example.com"] {
            XCTAssertTrue(client.matches(searchQuery: query), query)
        }
        for query in ["erika poodle", "muneca 9999", "missing muneca", "f:alvarado", "p:erika", "pet:", "unknown:erika", "erikaabc"] {
            XCTAssertFalse(client.matches(searchQuery: query), query)
        }
    }

    func testNumericPetNamesRemainSearchableWithoutAPhoneMatch() throws {
        let (client, pet) = try seedClient()
        pet.name = "Dog 42"
        XCTAssertTrue(client.matches(searchQuery: "dog 42"))
        XCTAssertFalse(client.matches(searchQuery: "p:42"))
    }

    func testFormattedPhoneAndPrefixesMatchWithoutNamePredicateDiscardingThem() async throws {
        let (client, _) = try seedClient()
        let repository = ClientRepository(modelContainer: container)
        for query in ["(323) 555-0123", "323-555-0123", "p:(323) 555-0123", "n:alvarado erika", "pet:muneca", "breed:golden", "erika muneca"] {
            let ids = try await repository.fetchClients(query: query, limit: 10, offset: 0)
            XCTAssertEqual(ids, [client.persistentModelID], query)
            let (inactive, _) = try await repository.fetchInactiveClients(query: query, limit: 10, offset: 0)
            XCTAssertEqual(inactive, ids, query)
        }
        let visit = Visit(pet: client.pets!.first!)
        context.insert(visit)
        try context.save()
        let active = try await repository.fetchActiveClients(query: "erika muneca")
        XCTAssertEqual(active, [client.persistentModelID])
    }

    func testFirstAndLastNameSortUseStableTieBreakersAndMissingNamesSortLast() {
        let erika = Client(firstName: "Erika", lastName: "Alvarado")
        let adam = Client(firstName: "Adam", lastName: "Zamora")
        let blank = Client(firstName: "  ", lastName: "  ")
        let same = Client(firstName: "Erika", lastName: "Alvarado")
        let clients = [erika, blank, adam, same]
        let first = ClientListOrdering.sorted(clients, by: .firstName)
        XCTAssertEqual(first.first?.uuid, adam.uuid)
        XCTAssertEqual(first.last?.uuid, blank.uuid)
        let last = ClientListOrdering.sorted(clients, by: .lastName)
        XCTAssertEqual(last.first?.lastName, "Alvarado")
        XCTAssertEqual(last.last?.uuid, blank.uuid)
        for option in ClientsViewModel.SortOption.allCases {
            XCTAssertEqual(ClientListOrdering.sorted(clients, by: option).map(\.uuid), ClientListOrdering.sorted(Array(clients.reversed()), by: option).map(\.uuid))
        }
    }

    func testCreatingAndRepeatedlySortingNeverDuplicatesFirstCardData() async throws {
        let (original, _) = try seedClient()
        let viewModel = ClientsViewModel(modelContext: context)
        await viewModel.waitForPendingFetch()
        let repository = ClientRepository(modelContainer: container)
        let id = try await repository.createClient(firstName: "Adam", lastName: "Zamora", phone: "+13235550101", email: "", address: "", photoData: nil, pets: [], contacts: [])
        for option in [.lastName, .firstName, .lastName, .newest] as [ClientsViewModel.SortOption] {
            viewModel.sortOption = option
            await viewModel.waitForPendingFetch()
            XCTAssertEqual(viewModel.otherClients.count, 2)
            XCTAssertEqual(Set(viewModel.otherClients.map(\.uuid)).count, 2)
            XCTAssertTrue(viewModel.otherClients.contains { $0.uuid == original.uuid })
            XCTAssertTrue(viewModel.otherClients.contains { $0.persistentModelID == id })
        }
    }

    func testInboxCreationReadAndDeletionSharePersistedCounts() async throws {
        let repository = ClientRepository(modelContainer: container)
        _ = try await repository.createClient(firstName: "Erika", lastName: "Alvarado", phone: "", email: "", address: "", photoData: nil, pets: [], contacts: [])
        let inbox = NotificationInbox()
        inbox.refresh(container: container)
        await inbox.waitForRefresh()
        XCTAssertEqual(inbox.unreadCount, 1)
        XCTAssertEqual(inbox.entries.first?.message, "Erika Alvarado")
        let id = try XCTUnwrap(inbox.entries.first?.id)
        await inbox.update(ids: [id], removing: false, container: container)
        XCTAssertEqual(inbox.unreadCount, 0)
        XCTAssertEqual(inbox.entries.count, 1, "Opening the inbox must not remove the notification.")
        let reopened = NotificationInbox()
        reopened.refresh(container: container)
        await reopened.waitForRefresh()
        XCTAssertEqual(reopened.entries.count, 1)
        XCTAssertEqual(reopened.unreadCount, 0)
        await inbox.update(ids: [id], removing: true, container: container)
        reopened.refresh(container: container)
        await reopened.waitForRefresh()
        XCTAssertTrue(reopened.entries.isEmpty)
    }

    func testPetAddEmitsNotificationAndImmediatelyBecomesSearchable() async throws {
        let (client, _) = try seedClient()
        let clientRepository = ClientRepository(modelContainer: container)
        let before = try await clientRepository.fetchClients(query: "luna", limit: 10, offset: 0)
        XCTAssertTrue(before.isEmpty)
        _ = try await PetEditorRepository(modelContainer: container).add(ownerID: client.persistentModelID, data: NewPetData(name: "Luna", species: .dog, gender: .female, breed: "Poodle", color: nil, photoData: nil, health: "Sensitive skin", behaviorTags: [], birthdate: nil))
        let results = try await clientRepository.fetchClients(query: "erika luna poodle", limit: 10, offset: 0)
        XCTAssertEqual(results, [client.persistentModelID])
        let inbox = try await NotificationRepository(modelContainer: container).entries()
        XCTAssertEqual(inbox.count, 1)
        XCTAssertTrue(inbox[0].message.contains("Luna"))
    }

    func testPetEditPreservesOtherContextChangesAndDecimalWeight() async throws {
        let (client, pet) = try seedClient()
        let baseline = PetEditFields(pet: pet)
        var edit = baseline
        edit.name = "Luna"
        edit.weight = Decimal(string: "12.35")!
        let other = ModelContext(container)
        let otherPet = try XCTUnwrap(other.model(for: pet.persistentModelID) as? Pet)
        otherPet.health = "Keep the medical note"
        otherPet.behaviorTags = ["Custom legacy tag"]
        try other.save()
        let saved = try await PetEditorRepository(modelContainer: container).save(id: pet.persistentModelID, fields: edit, baseline: baseline)
        XCTAssertEqual(saved.health, "Keep the medical note")
        XCTAssertEqual(saved.behaviorTags, ["Custom legacy tag"])
        XCTAssertEqual(saved.weight, Decimal(string: "12.35"))
        let ids = try await ClientRepository(modelContainer: container).fetchClients(query: "erika luna", limit: 10, offset: 0)
        XCTAssertEqual(ids, [client.persistentModelID])
    }

    func testRemoveAndRestoreKeepVisitsPaymentsAndOwner() async throws {
        let (client, pet) = try seedClient()
        let visit = Visit(pet: pet)
        visit.markCheckedOut(total: 45, now: .now)
        let payment = Payment(amount: 45, method: .cash)
        visit.payment = payment
        context.insert(visit)
        context.insert(payment)
        try context.save()
        let repository = PetEditorRepository(modelContainer: container)
        let archived = try await repository.setRemoved(id: pet.persistentModelID, removed: true)
        XCTAssertNotNil(archived)
        let fresh = ModelContext(container)
        let stored = try XCTUnwrap(fresh.model(for: pet.persistentModelID) as? Pet)
        XCTAssertEqual(stored.owner?.uuid, client.uuid)
        XCTAssertEqual(stored.visits?.count, 1)
        XCTAssertEqual(stored.visits?.first?.payment?.amount, 45)
        XCTAssertFalse(stored.owner!.matches(searchQuery: "muneca"))
        let restored = try await repository.setRemoved(id: pet.persistentModelID, removed: false)
        XCTAssertNil(restored)
        let results = try await ClientRepository(modelContainer: container).fetchClients(query: "muneca", limit: 10, offset: 0)
        XCTAssertEqual(results, [client.persistentModelID])
    }

    func testActiveSessionPreventsPetRemovalWithoutChangingData() async throws {
        let (_, pet) = try seedClient()
        context.insert(Visit(pet: pet))
        try context.save()
        do {
            _ = try await PetEditorRepository(modelContainer: container).setRemoved(id: pet.persistentModelID, removed: true)
            XCTFail("An active pet must not be removed.")
        } catch {
            let fresh = ModelContext(container)
            XCTAssertNil((fresh.model(for: pet.persistentModelID) as? Pet)?.archivedAt)
            XCTAssertEqual(try fresh.fetchCount(FetchDescriptor<Visit>()), 1)
        }
    }

    func testClientListModelReleasesWhileEventStreamStaysOpen() async {
        let bus = GlobalEventBus()
        var viewModel: ClientsViewModel? = ClientsViewModel(modelContext: context, eventBus: bus)
        await viewModel?.waitForPendingFetch()
        bus.publish(.refreshRequired)
        await Task.yield()
        await viewModel?.waitForPendingFetch()
        weak var released = viewModel
        viewModel = nil
        await Task.yield()
        XCTAssertNil(released, "The event stream must not retain a dismissed client list.")
    }

    func testInactivePaginationHasNoOverlapWhenActiveClientsSortBeforePageBoundary() async throws {
        let (activeOwner, pet) = try seedClient()
        context.insert(Visit(pet: pet))
        for index in 0..<6 { context.insert(Client(firstName: "First", lastName: "Zulu\(index)")) }
        try context.save()
        let repository = ClientRepository(modelContainer: container)
        let (first, more) = try await repository.fetchInactiveClients(query: "", limit: 3, offset: 0)
        let (second, lastMore) = try await repository.fetchInactiveClients(query: "", limit: 3, offset: 3)
        XCTAssertTrue(more); XCTAssertFalse(lastMore)
        XCTAssertEqual(Set(first + second).count, 6)
        XCTAssertFalse((first + second).contains(activeOwner.persistentModelID))
    }
}
