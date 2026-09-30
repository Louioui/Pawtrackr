//
//  ExportServiceTests.swift
//  PawtrackrTests
//
//  Verifies CSV export covers escaping, async path, and field-coverage so the
//  Settings export buttons produce well-formed files for any data set.
//

import XCTest
import SwiftData
@testable import Pawtrackr

@MainActor
final class ExportServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let schema = Schema(PawtrackrSchema.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [config])
        context = container.mainContext
    }

    override func tearDownWithError() throws {
        container = nil
        context = nil
        try super.tearDownWithError()
    }

    // MARK: - Sync (MainActor) path

    func testExportClientsToCSV_HeadersAndRows() throws {
        try seedTwoClients()

        let doc = try ExportService.shared.exportClientsToCSV(modelContext: context)

        let lines = doc.csvData.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        XCTAssertEqual(
            lines.first,
            "First Name,Last Name,Phone,Email,Address,Pets,Pet Count,Emergency Contact,Emergency Phone,Visits,Lifetime Spend,Average Visit,Loyalty Points,First Visit,Last Visit,Client Since,Notes,Client ID"
        )
        XCTAssertEqual(lines.count, 3, "1 header + 2 client rows")
        XCTAssertTrue(doc.filename.hasPrefix("Pawtrackr_Clients_"))
        XCTAssertTrue(doc.filename.hasSuffix(".csv"))
    }

    func testExportClientsToCSV_EscapesEmbeddedCommasAndQuotes() throws {
        let client = Client(
            firstName: "Ava, the Great",
            lastName: "O\"Brien",
            phone: "5550100100",
            email: "ava@example.com"
        )
        client.notes = "Likes \"squeaky\" toys, walks at dawn"
        context.insert(client)
        try context.save()

        let doc = try ExportService.shared.exportClientsToCSV(modelContext: context)
        XCTAssertTrue(doc.csvData.contains("\"Ava, the Great\""), "Names with commas must be quoted.")
        XCTAssertTrue(doc.csvData.contains("\"O\"\"Brien\""), "Embedded quotes must be doubled.")
    }

    // MARK: - Async (background context) path

    func testExportClientsToCSVAsync_ReturnsSameContentAsSync() async throws {
        try seedTwoClients()

        let asyncDoc = try await ExportService.shared.exportClientsToCSVAsync(container: container)
        let syncDoc = try ExportService.shared.exportClientsToCSV(modelContext: context)

        XCTAssertEqual(asyncDoc.csvData, syncDoc.csvData,
                       "Async path must produce byte-for-byte identical output.")
    }

    func testExportVisitsToCSVAsync_FormatsTotalsLocaleAgnostic() async throws {
        let pet = Pet(name: "Buddy", species: .dog)
        context.insert(pet)
        let visit = Visit(pet: pet, startedAt: .now)
        let payment = Payment(amount: Decimal(string: "1234.56")!, method: .cash, paidAt: .now)
        context.insert(payment)
        visit.attachPayment(payment)
        visit.markCheckedOut(total: Decimal(string: "1234.56")!, now: .now)
        context.insert(visit)
        try context.save()

        let doc = try await ExportService.shared.exportVisitsToCSVAsync(container: container)
        XCTAssertTrue(doc.csvData.contains(",1234.56,"),
                      "Totals must use a period decimal separator regardless of locale.")
    }

    func testExportEmptyStore_ReturnsHeaderOnlyDocument() async throws {
        let doc = try await ExportService.shared.exportClientsToCSVAsync(container: container)
        let lines = doc.csvData.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(lines[0].hasPrefix("First Name,"))
    }

    /// A client's row carries their pets, emergency contact and what their
    /// visits add up to, with dates and money a spreadsheet can use.
    func testClientRowsAddUpPetsVisitsAndSpend() throws {
        let client = Client(firstName: "Ava", lastName: "Martinez", phone: "3125550110", email: "ava@example.com")
        context.insert(client)
        let milo = Pet(name: "Milo", species: .dog)
        milo.owner = client
        context.insert(milo)
        let contact = EmergencyContact(name: "Rosa Diaz", relation: "Sister", phone: "3125550199")
        contact.owner = client
        context.insert(contact)
        let calendar = Calendar(identifier: .gregorian)
        for (day, total) in [(3, "40.00"), (17, "62.50")] {
            let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: 10)))
            let visit = Visit(pet: milo, startedAt: date)
            visit.markCheckedOut(total: try XCTUnwrap(Decimal(string: total)), now: date.addingTimeInterval(3_600))
            context.insert(visit)
        }
        try context.save()

        let doc = try ExportService.shared.exportClientsToCSV(modelContext: context)
        let row = try XCTUnwrap(doc.csvData.components(separatedBy: "\r\n").first { $0.hasPrefix("Ava,") })
        XCTAssertTrue(row.contains("Milo (Dog),1,Rosa Diaz (Sister),(312) 555-0199,2,102.50,51.25,"), row)
        XCTAssertTrue(row.contains(",(312) 555-0110,"), "Phones as the app shows them: \(row)")
        XCTAssertTrue(row.contains(",2026-09-03,2026-09-17,"), "First and last visit as yyyy-MM-dd: \(row)")
        XCTAssertTrue(row.hasSuffix(client.uuid.uuidString))
    }

    /// Each visit row says what was done and how it was paid.
    func testVisitRowsListServicesAndPayment() async throws {
        let owner = Client(firstName: "Jordan", lastName: "Lee", phone: "4155550142")
        context.insert(owner)
        let pet = Pet(name: "Biscuit", species: .cat)
        pet.owner = owner
        context.insert(pet)
        let service = Service(name: "Full Groom", category: .groom, basePrice: Decimal(85))
        context.insert(service)
        let start = try XCTUnwrap(Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 9, day: 12, hour: 9, minute: 30)))
        let visit = Visit(pet: pet, startedAt: start)
        context.insert(visit)
        let item = VisitItem.from(service: service, visit: visit)
        context.insert(item)
        visit.items = [item]
        let payment = Payment(amount: Decimal(85), method: .zelle, paidAt: start, externalReference: "ZL-889")
        context.insert(payment)
        visit.attachPayment(payment)
        visit.markCheckedOut(total: Decimal(85), now: start.addingTimeInterval(90 * 60))
        try context.save()

        let doc = try await ExportService.shared.exportVisitsToCSVAsync(container: container)
        let lines = doc.csvData.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].hasPrefix("Date,Check-In,Check-Out,Minutes,Client,"), lines[0])
        XCTAssertTrue(lines[1].hasPrefix("2026-09-12,09:30,11:00,90,Jordan Lee,(415) 555-0142,Biscuit,Cat,,Full Groom,85.00,85.00,Zelle,ZL-889,Completed,"), lines[1])
    }

    /// Excel reads the file as UTF-8 only with a byte order mark.
    func testSharedFileStartsWithAByteOrderMark() {
        let doc = ExportDocument(csvData: "Name\r\nJosé\r\n", filename: "x.csv")
        XCTAssertEqual(Array(doc.fileData.prefix(3)), [0xEF, 0xBB, 0xBF])
        XCTAssertEqual(String(data: doc.fileData.dropFirst(3), encoding: .utf8), doc.csvData)
    }

    // MARK: - Fixtures

    private func seedTwoClients() throws {
        let one = Client(
            firstName: "Ava",
            lastName: "Martinez",
            phone: "3125550110",
            email: "ava@example.com"
        )
        one.setAddress("42 Cedar Street")
        let two = Client(
            firstName: "Jordan",
            lastName: "Lee",
            phone: "4155550142",
            email: "jordan@example.com"
        )
        two.setAddress("18 Harbor Avenue")
        context.insert(one)
        context.insert(two)
        try context.save()
    }
}
