import XCTest
import SwiftData
@testable import Pawtrackr

final class PDFGenerationTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema(PawtrackrSchema.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
    }

    @MainActor
    func testReceiptSnapshot_BuildsCorrectData() throws {
        let owner = Client(firstName: "Jane", lastName: "Smith")
        owner.phone = "5551234567"
        context.insert(owner)
        
        let pet = Pet(name: "Bella", species: .dog)
        pet.owner = owner
        context.insert(pet)
        
        let visit = Visit(pet: pet, startedAt: Date())
        visit.total = Decimal(85)
        context.insert(visit)
        
        let service = Service(name: "Full Groom", category: .groom, basePrice: Decimal(85))
        context.insert(service)
        let item = VisitItem.from(service: service, visit: visit)
        context.insert(item)
        visit.items = [item]
        
        let payment = Payment(amount: Decimal(85), method: .creditCard, paidAt: Date())
        payment.externalReference = "TXN-123"
        context.insert(payment)
        visit.payment = payment
        
        try context.save()
        
        let snapshot = PDFReceiptService.shared.makeSnapshot(for: visit)
        
        XCTAssertEqual(snapshot.clientName, "Jane Smith")
        XCTAssertEqual(snapshot.totalString, "$85.00")
        XCTAssertEqual(snapshot.payment?.referenceLine, "Reference: TXN-123")
        XCTAssertTrue(snapshot.petLine.contains("Bella"))
    }
    
    @MainActor
    func testReportSnapshot_BuildsCorrectSummary() {
        let summary = BusinessReportService.MonthlySummary(
            month: Date(),
            totalRevenue: Decimal(5000),
            visitCount: 60,
            newClients: 5,
            topServices: [(name: "Bath", count: 20, revenue: Decimal(1000))],
            retentionRate: 0.85
        )
        
        let snapshot = BusinessReportService.shared.makeSnapshot(summary: summary)
        
        XCTAssertEqual(snapshot.totalRevenueString, "$5,000.00")
        XCTAssertEqual(snapshot.visitCountString, "60")
        XCTAssertEqual(snapshot.retentionString, "85%")
        XCTAssertEqual(snapshot.topServices.count, 1)
        XCTAssertEqual(snapshot.topServices.first?.name, "Bath")
    }
}
