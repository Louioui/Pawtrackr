import XCTest
import SwiftData
@testable import Pawtrackr

final class MigrationsTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema(PawtrackrSchema.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
    }

    func testMigrationPlanPreservesShippedSchemaChain() {
        XCTAssertEqual(PawtrackrSchemaV1.versionIdentifier, Schema.Version(1, 0, 6))
        XCTAssertEqual(PawtrackrSchemaV2.versionIdentifier, Schema.Version(1, 0, 7))
        XCTAssertEqual(PawtrackrSchemaV3.versionIdentifier, Schema.Version(1, 1, 0))
        XCTAssertEqual(PawtrackrSchemaV1.models.count, 19)
        XCTAssertEqual(PawtrackrSchemaV2.models.count, 20)
        XCTAssertEqual(PawtrackrSchemaV3.models.count, 22)
        XCTAssertEqual(PawtrackrMigrationPlan.schemas.count, 3)
        XCTAssertEqual(PawtrackrMigrationPlan.stages.count, 2)
    }

    func testCurrentMigrationPlanOpensShippedV1StoreWithClients() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PawtrackrMigrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let storeURL = directory.appendingPathComponent("Pawtrackr.store")

        try autoreleasepool {
            let oldSchema = Schema(PawtrackrSchemaV1.models)
            let oldConfig = ModelConfiguration(
                "Pawtrackr",
                schema: oldSchema,
                url: storeURL,
                cloudKitDatabase: .none
            )
            let oldContainer = try ModelContainer(for: oldSchema, configurations: [oldConfig])
            let oldContext = ModelContext(oldContainer)
            oldContext.insert(Client(firstName: "Legacy", lastName: "Client", phone: "555-0100"))
            try oldContext.save()
        }

        try autoreleasepool {
            let currentSchema = Schema(PawtrackrSchema.models)
            let currentConfig = ModelConfiguration(
                "Pawtrackr",
                schema: currentSchema,
                url: storeURL,
                cloudKitDatabase: .none
            )
            let migratedContainer = try ModelContainer(
                for: currentSchema,
                migrationPlan: PawtrackrMigrationPlan.self,
                configurations: [currentConfig]
            )
            let migratedContext = ModelContext(migratedContainer)
            let clients = try migratedContext.fetch(FetchDescriptor<Client>())

            XCTAssertEqual(clients.map(\.fullName), ["Legacy Client"])
            XCTAssertEqual(try migratedContext.fetchCount(FetchDescriptor<LoyaltyLedgerEntry>()), 0)
            XCTAssertEqual(try migratedContext.fetchCount(FetchDescriptor<LoyaltyConfig>()), 0)
            XCTAssertEqual(try migratedContext.fetchCount(FetchDescriptor<LoyaltyRewardTemplate>()), 0)
        }
    }

    func testEnsureServiceCatalog_CreatesDefaults() throws {
        // Initial state: potentially empty or seeded by container init
        // We'll clear and run the migration
        let existing = try context.fetch(FetchDescriptor<Service>())
        for s in existing { context.delete(s) }
        try context.save()
        
        DataMigrations.ensureServiceCatalog(in: context)
        
        let services = try context.fetch(FetchDescriptor<Service>())
        XCTAssertGreaterThan(services.count, 5)
        XCTAssertTrue(services.contains(where: { $0.name == "Full Package" }))
    }

    func testEnsureServiceCatalog_DisablesObsoleteBasicGroom() throws {
        let obsolete = Service(
            name: "Basic Groom",
            category: .groom,
            systemIcon: "scissors",
            basePrice: Decimal(50),
            isEnabled: true
        )
        context.insert(obsolete)
        try context.save()

        DataMigrations.ensureServiceCatalog(in: context)

        let services = try context.fetch(FetchDescriptor<Service>())
        let fetched = try XCTUnwrap(services.first(where: { $0.name == "Basic Groom" }))
        XCTAssertFalse(fetched.isEnabled)
        XCTAssertNil(fetched.basePrice)
    }

    func testEnsureMessageTemplates_AddsMissingDefaultsToExistingInstall() throws {
        let custom = MessageTemplate(title: "Custom Update", content: "Custom body")
        context.insert(custom)
        try context.save()

        DataMigrations.ensureMessageTemplates(in: context)

        let titles = Set(try context.fetch(FetchDescriptor<MessageTemplate>()).map(\.title))
        XCTAssertTrue(titles.contains("Custom Update"))
        XCTAssertTrue(titles.contains("Ready for Pickup"))
        XCTAssertTrue(titles.contains("Appointment Reminder"))
        XCTAssertTrue(titles.contains("Running Late"))
        XCTAssertTrue(titles.contains("Post-Visit Follow-up"))
    }

    func testEnsureLoyaltyDefaults_CreatesConfigAndRewardTemplates() throws {
        DataMigrations.ensureLoyaltyDefaults(in: context)

        let configs = try context.fetch(FetchDescriptor<LoyaltyConfig>())
        XCTAssertEqual(configs.count, 1)
        XCTAssertEqual(configs.first?.earnMode, .pointsPerDollar)
        XCTAssertEqual(configs.first?.pointsPerDollar, Decimal(1))
        XCTAssertEqual(configs.first?.pointsPerVisit, 20)
        XCTAssertEqual(configs.first?.redemptionThreshold, 100)

        let rewards = try context.fetch(
            FetchDescriptor<LoyaltyRewardTemplate>(sortBy: [SortDescriptor(\.sortOrder)])
        )
        XCTAssertEqual(rewards.count, LoyaltyReward.builtInCatalog.count)
        XCTAssertEqual(rewards.first?.pointCost, 100)
    }

    func testEnsureLoyaltyDefaults_IsIdempotent() throws {
        DataMigrations.ensureLoyaltyDefaults(in: context)
        DataMigrations.ensureLoyaltyDefaults(in: context)

        XCTAssertEqual(try context.fetch(FetchDescriptor<LoyaltyConfig>()).count, 1)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<LoyaltyRewardTemplate>()).count,
            LoyaltyReward.builtInCatalog.count
        )
    }

    func testEnsureLoyaltyDefaults_CollapsesAllDuplicateConfigs() throws {
        context.insert(LoyaltyConfig())
        context.insert(LoyaltyConfig())
        context.insert(LoyaltyConfig())
        try context.save()

        DataMigrations.ensureLoyaltyDefaults(in: context)

        XCTAssertEqual(try context.fetch(FetchDescriptor<LoyaltyConfig>()).count, 1)
    }

    func testEnsureLoyaltyDefaults_MergesDuplicateConfigsFieldWise() throws {
        let baseline = LoyaltyConfig()
        baseline.createdAt = Date(timeIntervalSince1970: 10)
        baseline.updatedAt = Date(timeIntervalSince1970: 10)

        let earningRules = LoyaltyConfig()
        earningRules.setEarnMode(.flatPerVisit)
        earningRules.setPointsPerVisit(80)
        earningRules.createdAt = Date(timeIntervalSince1970: 20)
        earningRules.updatedAt = Date(timeIntervalSince1970: 20)

        let rewardRules = LoyaltyConfig()
        rewardRules.setPointsPerDollar(Decimal(3))
        rewardRules.setRedemptionThreshold(275)
        rewardRules.setRewardsCatalogEnabled(false)
        rewardRules.createdAt = Date(timeIntervalSince1970: 30)
        rewardRules.updatedAt = Date(timeIntervalSince1970: 30)

        context.insert(baseline)
        context.insert(earningRules)
        context.insert(rewardRules)
        try context.save()

        DataMigrations.ensureLoyaltyDefaults(in: context)

        let configs = try context.fetch(FetchDescriptor<LoyaltyConfig>())
        let config = try XCTUnwrap(configs.first)
        XCTAssertEqual(configs.count, 1)
        XCTAssertEqual(config.earnMode, .flatPerVisit)
        XCTAssertEqual(config.pointsPerDollar, Decimal(3))
        XCTAssertEqual(config.pointsPerVisit, 80)
        XCTAssertEqual(config.redemptionThreshold, 275)
        XCTAssertFalse(config.isRewardsCatalogEnabled)
    }
    
    func testCoercePets_StandardizesGenders() throws {
        let client = Client(firstName: "Test", lastName: "Owner")
        let pet = Pet(name: "Test", species: .dog)
        pet.genderRaw = "legacy-invalid"
        pet.owner = client
        client.pets = [pet]
        context.insert(client)
        try context.save()

        DataMigrations.coercePets(in: context)
        
        let fetched = try context.fetch(FetchDescriptor<Pet>()).first!
        XCTAssertEqual(fetched.genderRaw, PetGender.male.rawValue)
    }
}
