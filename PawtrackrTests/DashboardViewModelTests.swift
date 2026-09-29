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
    //
    // Every checklist test injects the backup status, so the host's iCloud
    // account and UserDefaults never decide the outcome.

    private final class StatusBox {
        var status: BackupStatus
        init(_ status: BackupStatus) { self.status = status }
    }

    private func makeViewModel(backupStatus: BackupStatus = .notBackedUp(localChangesSince: nil)) -> DashboardViewModel {
        DashboardViewModel(dataStore: dataStore, eventBus: eventBus, backupStatus: { backupStatus })
    }

    private func row(_ action: DashboardViewModel.ChecklistAction, in vm: DashboardViewModel) -> DashboardViewModel.ChecklistItem? {
        vm.checklist.first { $0.action == action }
    }

    func testRefresh_ChecklistReportsAllStepsIncompleteOnEmptyStore() async {
        let vm = makeViewModel()
        await vm.refresh()

        XCTAssertEqual(vm.checklist.map(\.action), [.branding, .addClient, .firstVisit, .iCloudBackup])
        XCTAssertTrue(vm.checklist.allSatisfy { !$0.isCompleted },
                      "Empty store: every checklist step should be incomplete.")
        XCTAssertFalse(vm.isChecklistComplete)
        XCTAssertFalse(vm.hasSampleData)
    }

    func testChecklistIsEmptyUntilTheStoreHasBeenRead() {
        let vm = makeViewModel(backupStatus: .backedUp(asOf: Date()))
        XCTAssertTrue(vm.checklist.isEmpty)
        XCTAssertFalse(vm.isChecklistComplete, "Nothing loaded is not the same as everything done.")
    }

    /// Only iCloud's confirmed upload ("Backed up") ticks the backup row.
    func testBackupRow_OnlyConfirmedUploadCounts() async {
        let statuses: [(BackupStatus, Bool)] = [
            (.backedUp(asOf: Date()), true),
            (.uploading, false),
            (.notBackedUp(localChangesSince: nil), false),
            (.notBackedUp(localChangesSince: Date()), false),
            (.failing(since: Date(), disposition: .transient), false),
            (.localOnly, false),
            (.signedOut, false),
            (.unknown, false)
        ]
        for (status, expected) in statuses {
            XCTAssertEqual(DashboardViewModel.hasBackupProtection(status), expected, "\(status)")
            let vm = makeViewModel(backupStatus: status)
            await vm.refresh()
            XCTAssertEqual(row(.iCloudBackup, in: vm)?.isCompleted, expected, "\(status)")
        }
        XCTAssertFalse(SecureStoreSnapshotExporter.isUserFacingExportEnabled,
                       "The raw-store snapshot has no restore path; it must stay hidden.")
    }

    /// Regression: a same-device encrypted snapshot (which nothing can
    /// restore, and whose key never leaves the device) used to tick
    /// "Confirm Backup Protection".
    func testRefresh_LocalSnapshotDoesNotCountAsBackupProtection() async {
        let key = SecureStoreSnapshotExporter.lastSuccessfulSnapshotDateKey
        let previous = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(previous, forKey: key) }
        UserDefaults.standard.set(Date(), forKey: key)

        let vm = makeViewModel(backupStatus: .localOnly)
        await vm.refresh()
        XCTAssertEqual(row(.iCloudBackup, in: vm)?.isCompleted, false, "A local snapshot must not count as backup protection.")
    }

    func testBackupRowFollowsTheStatusWithoutARefresh() async {
        let box = StatusBox(.uploading)
        let vm = DashboardViewModel(dataStore: dataStore, eventBus: eventBus, backupStatus: { box.status })
        await vm.refresh()
        XCTAssertEqual(row(.iCloudBackup, in: vm)?.isCompleted, false)

        box.status = .backedUp(asOf: Date())
        XCTAssertEqual(row(.iCloudBackup, in: vm)?.isCompleted, true)

        box.status = .notBackedUp(localChangesSince: Date())
        XCTAssertEqual(row(.iCloudBackup, in: vm)?.isCompleted, false, "The row is live, which is why the card latches once done.")
    }

    func testBrandingNeedsALogoOrContactDetails() async throws {
        let config = BusinessConfig()
        config.name = "My Shop"
        config.isSetupComplete = true
        context.insert(config)
        try context.save()

        let vm = makeViewModel()
        await vm.refresh()
        XCTAssertEqual(row(.branding, in: vm)?.isCompleted, false, "A name alone isn't branding: onboarding always sets one.")

        config.phone = "   "
        try context.save()
        await vm.refresh()
        XCTAssertEqual(row(.branding, in: vm)?.isCompleted, false, "Whitespace isn't a phone number.")

        config.phone = "5550100199"
        try context.save()
        await vm.refresh()
        XCTAssertEqual(row(.branding, in: vm)?.isCompleted, true)

        config.phone = nil
        config.email = "hello@example.com"
        try context.save()
        await vm.refresh()
        XCTAssertEqual(row(.branding, in: vm)?.isCompleted, true)

        config.email = nil
        config.logoData = Data([0x89, 0x50, 0x4E, 0x47])
        try context.save()
        await vm.refresh()
        XCTAssertEqual(row(.branding, in: vm)?.isCompleted, true)
    }

    /// Nothing in the app sets a service's price except sample data, so a
    /// prices row could never be finished by a real salon. The checklist has
    /// no such row, and a priced service changes nothing.
    func testRefresh_ChecklistHasNoServicePricesRow() async throws {
        let svc = Service(name: "Bath", basePrice: 25)
        context.insert(svc)
        try context.save()

        let vm = makeViewModel()
        await vm.refresh()

        XCTAssertEqual(Set(vm.checklist.map(\.action)), Set(DashboardViewModel.ChecklistAction.allCases))
        XCTAssertEqual(DashboardViewModel.ChecklistAction.allCases.count, 4)
        XCTAssertTrue(vm.checklist.allSatisfy { !$0.isCompleted })
    }

    func testRefresh_ChecklistFlipsClientWhenAtLeastOneClient() async throws {
        let client = Client(firstName: "Ava", lastName: "Test", phone: "5550100199")
        context.insert(client)
        try context.save()

        let vm = makeViewModel()
        await vm.refresh()

        XCTAssertEqual(row(.addClient, in: vm)?.isCompleted, true)
        XCTAssertEqual(row(.firstVisit, in: vm)?.isCompleted, false)
    }

    /// Sample clients and their visits are identified by the fixed sample
    /// UUIDs, never by name, and don't finish "your first client/visit".
    func testSampleClientsAndVisitsDontCountAsTheSalonsOwn() async throws {
        let sample = Client(firstName: "Ava", lastName: "Martinez", phone: "5550100199")
        sample.uuid = SampleData.avaClientID
        let samplePet = Pet(name: "Milo", species: .dog)
        samplePet.uuid = SampleData.miloPetID
        samplePet.owner = sample
        context.insert(sample)
        context.insert(samplePet)
        // A visit the tour or a user added on the sample pet: random UUID.
        let visitOnSample = Visit(pet: samplePet, startedAt: .now)
        context.insert(visitOnSample)
        try context.save()

        let vm = makeViewModel()
        await vm.refresh()
        XCTAssertTrue(vm.hasSampleData)
        XCTAssertEqual(row(.addClient, in: vm)?.isCompleted, false)
        XCTAssertEqual(row(.firstVisit, in: vm)?.isCompleted, false)

        // A real client with the same name, and a visit of their own.
        let real = Client(firstName: "Ava", lastName: "Martinez", phone: "5550100200")
        let realPet = Pet(name: "Milo", species: .dog)
        realPet.owner = real
        context.insert(real)
        context.insert(realPet)
        context.insert(Visit(pet: realPet, startedAt: .now))
        try context.save()

        await vm.refresh()
        XCTAssertEqual(row(.addClient, in: vm)?.isCompleted, true)
        XCTAssertEqual(row(.firstVisit, in: vm)?.isCompleted, true)
    }

    func testChecklistCompletesOnlyWhenEveryRowIsDone() async throws {
        let config = BusinessConfig(name: "My Shop", phone: "5550100199")
        context.insert(config)
        let client = Client(firstName: "Ava", lastName: "Test", phone: "5550100199")
        let pet = Pet(name: "Luna", species: .dog)
        pet.owner = client
        context.insert(client)
        context.insert(pet)
        context.insert(Visit(pet: pet, startedAt: .now))
        try context.save()

        let box = StatusBox(.uploading)
        let vm = DashboardViewModel(dataStore: dataStore, eventBus: eventBus, backupStatus: { box.status })
        await vm.refresh()
        XCTAssertFalse(vm.isChecklistComplete, "Everything but the backup.")

        box.status = .backedUp(asOf: Date())
        XCTAssertTrue(vm.isChecklistComplete)

        XCTAssertFalse(DashboardViewModel.isComplete([]))
    }

    func testChecklistRowsOpenTheirOwnSettingsSection() {
        XCTAssertEqual(DashboardViewModel.ChecklistAction.branding.settingsSection, .business)
        XCTAssertEqual(DashboardViewModel.ChecklistAction.iCloudBackup.settingsSection, .icloud)
        XCTAssertNil(DashboardViewModel.ChecklistAction.addClient.settingsSection)
        XCTAssertNil(DashboardViewModel.ChecklistAction.firstVisit.settingsSection)
    }

    /// The deep link carries the section; ContentView opens it after the
    /// surface switch, which resets the Settings path.
    func testSettingsDeepLinkOpensTheSectionAfterTheSurfaceSwitch() {
        let note = Notification(name: .selectNavigationItem, object: nil, userInfo: [
            NavigationSelectionKey.item.rawValue: NavigationItem.settings.rawValue,
            NavigationSelectionKey.resetPath.rawValue: true,
            NavigationSelectionKey.settingsSection.rawValue: SettingSection.icloud.rawValue
        ])
        XCTAssertEqual(note.requestedNavigationItem, .settings)
        XCTAssertEqual(note.requestedSettingsSection, .icloud)

        let router = NavigationRouter()
        router.activeNavigationItem = .settings
        router.popToRoot()
        router.openSettingsSection(.business)
        #if os(macOS)
        XCTAssertEqual(router.requestedSettingsSection, .business)
        #else
        XCTAssertEqual(router.settingsPath.count, 1)
        #endif
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

    func testVisitDidCompleteFiltersStaleActiveVisitID() async throws {
        let pet = Pet(name: "Milo", species: .dog)
        context.insert(pet)
        let visit = Visit(pet: pet, startedAt: .now)
        context.insert(visit)
        try context.save()

        let repository = MockDashboardRepository()
        repository.activeVisits = [visit.persistentModelID]
        repository.kpi.inProgressCount = 1

        let vm = DashboardViewModel(dataStore: dataStore, eventBus: eventBus, repository: repository)
        try? await Task.sleep(for: .milliseconds(150))
        await vm.refresh()

        XCTAssertEqual(vm.activeVisits.count, 1)
        XCTAssertEqual(vm.kpi.inProgressCount, 1)

        NotificationCenter.default.post(
            name: .visitDidComplete,
            object: nil,
            userInfo: [
                VisitDidCompleteKey.visitID.rawValue: visit.persistentModelID,
                VisitDidCompleteKey.endedAt.rawValue: Date(),
                VisitDidCompleteKey.total.rawValue: Decimal(30)
            ]
        )

        let deadline = Date().addingTimeInterval(2)
        // Wait for BOTH reconciled signals before asserting — KPI can lag the
        // activeVisits update by a tick, which made this test intermittently flaky.
        while Date() < deadline, (!vm.activeVisits.isEmpty || vm.kpi.inProgressCount != 0) {
            try? await Task.sleep(for: .milliseconds(50))
        }

        XCTAssertTrue(vm.activeVisits.isEmpty)
        XCTAssertEqual(vm.kpi.inProgressCount, 0)
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
