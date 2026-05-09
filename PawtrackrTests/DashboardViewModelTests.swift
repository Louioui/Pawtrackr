//
//  DashboardViewModelTests.swift
//  PawtrackrTests
//
//  Verifies the dashboard's @Observable view-model coordinates KPIs, checklist,
//  active visits, and the check-in actions wired to its buttons.
//

import XCTest
import SwiftData
@testable import Pawtrackr

@MainActor
final class DashboardViewModelTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var dataStore: DataStoreService!
    private var eventBus: GlobalEventBus!

    override func setUpWithError() throws {
        try super.setUpWithError()

        let schema = Schema(PawtrackrSchema.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [config])
        context = container.mainContext
        dataStore = DataStoreService(container: container)
        eventBus = GlobalEventBus()
    }

    override func tearDownWithError() throws {
        container = nil
        context = nil
        dataStore = nil
        eventBus = nil
        try super.tearDownWithError()
    }

    // MARK: - Initial State

    func testInit_StartsRefreshTask() async {
        let vm = DashboardViewModel(dataStore: dataStore, eventBus: eventBus)

        // Init kicks off a refresh internally — give it a beat to finish so we
        // can verify it doesn't crash on empty data.
        try? await Task.sleep(for: .milliseconds(150))

        XCTAssertNotNil(vm)
        XCTAssertNil(vm.appError)
    }

    // MARK: - Checklist

    func testRefresh_ChecklistReportsAllStepsIncompleteOnEmptyStore() async {
        let vm = DashboardViewModel(dataStore: dataStore, eventBus: eventBus)
        await vm.refresh()

        XCTAssertEqual(vm.checklist.count, 4)
        XCTAssertTrue(vm.checklist.allSatisfy { !$0.isCompleted },
                      "Empty store: every checklist step should be incomplete.")
    }

    func testRefresh_ChecklistFlipsBrandingWhenSetupComplete() async throws {
        let config = BusinessConfig()
        config.name = "My Shop"
        config.isSetupComplete = true
        context.insert(config)
        try context.save()

        let vm = DashboardViewModel(dataStore: dataStore, eventBus: eventBus)
        await vm.refresh()

        let branding = vm.checklist.first(where: { $0.title.contains("Branding") })
        XCTAssertEqual(branding?.isCompleted, true)
    }

    func testRefresh_ChecklistFlipsCatalogWhenServicePriced() async throws {
        let svc = Service(name: "Bath", basePrice: 25)
        context.insert(svc)
        try context.save()

        let vm = DashboardViewModel(dataStore: dataStore, eventBus: eventBus)
        await vm.refresh()

        let catalog = vm.checklist.first(where: { $0.title.contains("Service Prices") })
        XCTAssertEqual(catalog?.isCompleted, true)
    }

    func testRefresh_ChecklistFlipsClientWhenAtLeastOneClient() async throws {
        let client = Client(firstName: "Ava", lastName: "Test", phone: "5550100199")
        context.insert(client)
        try context.save()

        let vm = DashboardViewModel(dataStore: dataStore, eventBus: eventBus)
        await vm.refresh()

        let item = vm.checklist.first(where: { $0.title.contains("First Client") })
        XCTAssertEqual(item?.isCompleted, true)
    }

    // MARK: - Active Visits & KPIs

    func testRefresh_ActiveVisitAppearsInActiveVisits() async throws {
        let pet = Pet(name: "Milo", species: .dog)
        context.insert(pet)
        let visit = Visit(pet: pet, startedAt: .now)
        context.insert(visit)
        try context.save()

        let vm = DashboardViewModel(dataStore: dataStore, eventBus: eventBus)
        await vm.refresh()

        XCTAssertEqual(vm.activeVisits.count, 1)
        XCTAssertEqual(vm.activeVisits.first?.pet?.name, "Milo")
        XCTAssertEqual(vm.kpi.inProgressCount, 1)
    }

    func testRefresh_RevenueSeriesIsAlwaysSevenDays() async {
        let vm = DashboardViewModel(dataStore: dataStore, eventBus: eventBus)
        await vm.refresh()

        XCTAssertEqual(vm.revenueSeries.count, 7,
                       "Revenue series should always render 7 buckets, even with no data.")
    }

    // MARK: - Check-In Actions

    func testCheckInPet_CreatesActiveVisit() async throws {
        let pet = Pet(name: "Luna", species: .dog)
        context.insert(pet)
        try context.save()

        let vm = DashboardViewModel(dataStore: dataStore, eventBus: eventBus)
        await vm.checkInPet(pet)

        // Wait for the refresh that follows checkIn.
        try? await Task.sleep(for: .milliseconds(150))

        XCTAssertNotNil(pet.activeVisit, "Check-in should attach an active visit to the pet.")
    }

    func testCheckInPet_NoOpWhenAlreadyHasActiveVisit() async throws {
        let pet = Pet(name: "Luna", species: .dog)
        context.insert(pet)
        let existing = Visit(pet: pet, startedAt: .now)
        context.insert(existing)
        try context.save()

        let vm = DashboardViewModel(dataStore: dataStore, eventBus: eventBus)
        await vm.checkInPet(pet)

        // The predicate macro can't unify Optional<UUID> with UUID, so filter
        // in-memory after fetching by visit count instead.
        let allVisits = try context.fetch(FetchDescriptor<Visit>())
        let petVisits = allVisits.filter { $0.pet?.uuid == pet.uuid }
        XCTAssertEqual(petVisits.count, 1, "Should not create a second visit when one is in flight.")
    }
}
