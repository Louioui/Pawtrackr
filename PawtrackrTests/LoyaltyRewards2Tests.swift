import XCTest
import SwiftData
@testable import Pawtrackr

/// Loyalty 2.0: the four cash-off rewards, their checkout pricing, moving
/// untouched 1.x catalogs to them, and spending a reward inside a checkout.
@MainActor
final class LoyaltyRewards2Tests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

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

    // MARK: - Catalog

    func testStarterCatalogIsTheFourCashOffRewards() {
        let catalog = LoyaltyReward.builtInCatalog
        XCTAssertEqual(catalog.map(\.title), ["$5 Off", "$20 Off", "25% Off", "Free Bath"])
        XCTAssertEqual(catalog.map(\.benefit), [
            .amountOff(Decimal(5)),
            .amountOff(Decimal(20)),
            .percentOff(Decimal(25)),
            .freeBath
        ])
        XCTAssertTrue(catalog.allSatisfy(\.benefit.appliesAtCheckout))
        XCTAssertEqual(Set(catalog.map(\.id)).count, catalog.count)
    }

    func testBenefitSurvivesTemplateStorage() {
        for reward in LoyaltyReward.builtInCatalog {
            let template = LoyaltyRewardTemplate(reward: reward, sortOrder: 0)
            XCTAssertEqual(template.displayReward.benefit, reward.benefit, reward.title)
        }
    }

    func testUnknownOrEmptyBenefitReadsAsManual() {
        XCTAssertEqual(LoyaltyReward.Benefit(kindRaw: "", value: 0), .manual)
        XCTAssertEqual(LoyaltyReward.Benefit(kindRaw: "someFutureKind", value: 9), .manual)
        XCTAssertEqual(LoyaltyReward.Benefit(kindRaw: "amountOff", value: 0), .manual, "Zero off is no benefit.")
        XCTAssertEqual(LoyaltyReward.Benefit(kindRaw: "percentOff", value: 250), .percentOff(100))
    }

    // MARK: - Pricing

    func testAmountOffIsCappedAtTheSubtotal() {
        XCTAssertEqual(LoyaltyRewardPricing.discount(for: .amountOff(5), subtotal: 80, bathPrice: nil), Decimal(5))
        XCTAssertEqual(LoyaltyRewardPricing.discount(for: .amountOff(20), subtotal: Decimal(string: "12.50")!, bathPrice: nil), Decimal(string: "12.50"))
    }

    func testPercentOffRoundsToCents() {
        // 25% of $67.30 = $16.825, banker's rounding → $16.82.
        XCTAssertEqual(
            LoyaltyRewardPricing.discount(for: .percentOff(25), subtotal: Decimal(string: "67.30")!, bathPrice: nil),
            Decimal(string: "16.82")
        )
    }

    func testFreeBathNeedsAPricedBathService() {
        XCTAssertEqual(LoyaltyRewardPricing.discount(for: .freeBath, subtotal: 90, bathPrice: 35), Decimal(35))
        XCTAssertEqual(LoyaltyRewardPricing.discount(for: .freeBath, subtotal: 20, bathPrice: 35), Decimal(20))
        XCTAssertNil(LoyaltyRewardPricing.discount(for: .freeBath, subtotal: 90, bathPrice: nil))
    }

    func testNothingDiscountsAnEmptyTicketOrAManualReward() {
        XCTAssertNil(LoyaltyRewardPricing.discount(for: .amountOff(5), subtotal: 0, bathPrice: nil))
        XCTAssertNil(LoyaltyRewardPricing.discount(for: .manual, subtotal: 80, bathPrice: nil))
    }

    func testBathPriceFindsTheBuiltInBathService() {
        let services = [
            Service(name: "Haircut", category: .groom, basePrice: Decimal(40)),
            Service(name: "Bath", category: .groom, basePrice: Decimal(30))
        ]
        XCTAssertEqual(CheckoutViewModel.bathPrice(in: services), Decimal(30))
        XCTAssertNil(CheckoutViewModel.bathPrice(in: [services[0]]))
    }

    // MARK: - Upgrading 1.x catalogs

    func testUntouchedLegacyCatalogMovesToRewards2() throws {
        insertLegacyCatalog()
        try context.save()

        DataMigrations.ensureLoyaltyDefaults(in: context)

        let rewards = try context.fetch(FetchDescriptor<LoyaltyRewardTemplate>(sortBy: [SortDescriptor(\.sortOrder)]))
        XCTAssertEqual(rewards.map(\.title), LoyaltyReward.builtInCatalog.map(\.title))
        XCTAssertEqual(rewards.map(\.benefit), LoyaltyReward.builtInCatalog.map(\.benefit))
        XCTAssertEqual(rewards.map(\.pointCost), LoyaltyReward.builtInCatalog.map(\.pointCost))

        DataMigrations.ensureLoyaltyDefaults(in: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LoyaltyRewardTemplate>()), LoyaltyReward.builtInCatalog.count, "Running again changes nothing.")
    }

    func testEditedLegacyCatalogIsLeftAlone() throws {
        let templates = insertLegacyCatalog()
        templates[1].pointCost = 120
        try context.save()

        DataMigrations.ensureLoyaltyDefaults(in: context)

        let rewards = try context.fetch(FetchDescriptor<LoyaltyRewardTemplate>(sortBy: [SortDescriptor(\.sortOrder)]))
        XCTAssertEqual(rewards.count, LoyaltyReward.legacyStarterCatalog.count)
        XCTAssertEqual(rewards.map(\.title), LoyaltyReward.legacyStarterCatalog.map(\.title))
        XCTAssertTrue(rewards.allSatisfy { $0.benefit == .manual })
    }

    // MARK: - Spending a reward at checkout

    func testCheckoutSpendsTheRewardAndEarnsOnTheNetTotal() async throws {
        let (client, pet) = try seedClient(points: 300)
        let visitUUID = UUID()
        let redemption = CheckoutRewardRedemption(rewardID: "twenty-off", title: "$20 Off", pointCost: 200, discount: 20)

        let actor = CheckoutTransactionActor(modelContainer: container)
        _ = try await actor.process(request(visitUUID: visitUUID, pet: pet, client: client, amount: 60, redemption: redemption))

        let fresh = ModelContext(container)
        let clientUUID = client.uuid
        let saved = try XCTUnwrap(try fresh.fetch(FetchDescriptor<Client>(predicate: #Predicate { $0.uuid == clientUUID })).first)
        // 300 - 200 spent + 60 earned on the $60 actually paid.
        XCTAssertEqual(saved.loyaltyPoints, 160)

        let entries = try fresh.fetch(FetchDescriptor<LoyaltyLedgerEntry>(predicate: #Predicate { $0.visitUUID == visitUUID }))
        let redeemed = try XCTUnwrap(entries.first { $0.kind == .redeemed })
        XCTAssertEqual(redeemed.points, -200)
        XCTAssertEqual(redeemed.reason, "$20 Off")
        XCTAssertEqual(entries.first { $0.kind == .earned }?.points, 60)
    }

    func testRedemptionIsSpentOncePerVisit() throws {
        let (client, _) = try seedClient(points: 300)
        let visitUUID = UUID()
        let redemption = CheckoutRewardRedemption(rewardID: "five-off", title: "$5 Off", pointCost: 50, discount: 5)

        XCTAssertTrue(LoyaltyCheckoutProcessor.applyRedemption(redemption, visitUUID: visitUUID, client: client, in: context))
        XCTAssertFalse(LoyaltyCheckoutProcessor.applyRedemption(redemption, visitUUID: visitUUID, client: client, in: context))
        XCTAssertEqual(client.loyaltyPoints, 250)
        XCTAssertTrue(LoyaltyCheckoutProcessor.canAfford(redemption, client: client, visitUUID: visitUUID, in: context),
                      "Points this visit already spent count toward affording it again.")

        XCTAssertTrue(LoyaltyCheckoutProcessor.applyRedemption(nil, visitUUID: visitUUID, client: client, in: context))
        XCTAssertEqual(client.loyaltyPoints, 300, "Dropping the reward on a retry refunds it.")
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LoyaltyLedgerEntry>()), 0)
    }

    func testCheckoutFailsCleanWhenTheClientCantAffordTheReward() async throws {
        let (client, pet) = try seedClient(points: 40)
        let redemption = CheckoutRewardRedemption(rewardID: "five-off", title: "$5 Off", pointCost: 50, discount: 5)
        let actor = CheckoutTransactionActor(modelContainer: container)

        do {
            _ = try await actor.process(request(visitUUID: UUID(), pet: pet, client: client, amount: 75, redemption: redemption))
            XCTFail("A reward the client can't afford must fail the checkout.")
        } catch {}

        let fresh = ModelContext(container)
        let clientUUID = client.uuid
        let saved = try XCTUnwrap(try fresh.fetch(FetchDescriptor<Client>(predicate: #Predicate { $0.uuid == clientUUID })).first)
        XCTAssertEqual(saved.loyaltyPoints, 40)
        XCTAssertEqual(try fresh.fetchCount(FetchDescriptor<Payment>()), 0)
    }

    // MARK: - Draft

    func testDraftsWrittenBefore2_0DecodeWithoutAReward() throws {
        let draft = CheckoutDraft(
            visitID: UUID(), petID: UUID(), currentStepRawValue: 2, sessionNotes: "", amountString: "80.00",
            selectedServiceUUIDs: [], selectedAddOnUUIDs: [], selectedPaymentMethodRawValue: "cash",
            beforePhotoData: nil, afterPhotoData: nil, externalReference: "", tags: [], appliedRewardID: "free-bath"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let roundTrip = try decoder.decode(CheckoutDraft.self, from: encoder.encode(draft))
        XCTAssertEqual(roundTrip.appliedRewardID, "free-bath")

        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(draft)) as? [String: Any])
        json.removeValue(forKey: "appliedRewardID")
        let legacy = try decoder.decode(CheckoutDraft.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(legacy.appliedRewardID)
    }

    // MARK: - Helpers

    @discardableResult
    private func insertLegacyCatalog() -> [LoyaltyRewardTemplate] {
        LoyaltyReward.legacyStarterCatalog.enumerated().map { index, reward in
            let template = LoyaltyRewardTemplate(reward: reward, sortOrder: index)
            context.insert(template)
            return template
        }
    }

    private func seedClient(points: Int) throws -> (Client, Pet) {
        let client = Client(firstName: "Ava", lastName: "Martinez")
        client.loyaltyPoints = points
        context.insert(client)
        let pet = Pet(name: "Biscuit", species: .dog)
        pet.owner = client
        context.insert(pet)
        try context.save()
        return (client, pet)
    }

    private func request(visitUUID: UUID, pet: Pet, client: Client, amount: Decimal, redemption: CheckoutRewardRedemption?) -> CheckoutRequest {
        CheckoutRequest(
            visitUUID: visitUUID,
            petUUID: pet.uuid,
            clientUUID: client.uuid,
            amount: amount,
            paymentMethod: .cash,
            externalReference: nil,
            sessionNotes: nil,
            behaviorTags: [],
            beforePhotoData: nil,
            afterPhotoData: nil,
            selectedServiceIDs: [],
            selectedAddOnIDs: [],
            rewardRedemption: redemption
        )
    }
}
