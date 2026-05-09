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

        let lines = doc.csvData.components(separatedBy: "\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.first, "First Name,Last Name,Phone,Email,Address,Notes,Last Visit")
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
        let payment = Payment(amount: 1234.56, method: .cash, paidAt: .now)
        context.insert(payment)
        visit.attachPayment(payment)
        visit.markCheckedOut(total: 1234.56, now: .now)
        context.insert(visit)
        try context.save()

        let doc = try await ExportService.shared.exportVisitsToCSVAsync(container: container)
        XCTAssertTrue(doc.csvData.contains(",1234.56,"),
                      "Totals must use a period decimal separator regardless of locale.")
    }

    func testExportEmptyStore_ReturnsHeaderOnlyDocument() async throws {
        let doc = try await ExportService.shared.exportClientsToCSVAsync(container: container)
        let lines = doc.csvData.components(separatedBy: "\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(lines[0].hasPrefix("First Name,"))
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
