import Foundation
import SwiftData
import UniformTypeIdentifiers
import CoreTransferable

public struct ExportDocument: Transferable, Identifiable {
    let csvData: String
    let filename: String

    public var id: String { filename }

    public static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { doc in
            doc.csvData.data(using: .utf8) ?? Data()
        }
        .suggestedFileName { doc in doc.filename }
    }
}

struct ReceiptDocument: Transferable {
    let pdfData: Data
    let filename: String
    
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .pdf) { doc in
            doc.pdfData
        }
        .suggestedFileName { doc in doc.filename }
    }
}

struct ReportDocument: Transferable {
    let pdfData: Data
    let filename: String
    
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .pdf) { doc in
            doc.pdfData
        }
        .suggestedFileName { doc in doc.filename }
    }
}

final class ExportService: @unchecked Sendable {
    static let shared = ExportService()

    @MainActor
    func exportClientsToCSV(modelContext: ModelContext) throws -> ExportDocument {
        let descriptor = FetchDescriptor<Client>(sortBy: [SortDescriptor(\.lastName), SortDescriptor(\.firstName)])
        let clients = try modelContext.fetch(descriptor)
        return Self.makeClientsCSV(from: clients, dateString: Self.currentDateString())
    }

    @MainActor
    func exportVisitsToCSV(modelContext: ModelContext) throws -> ExportDocument {
        let descriptor = FetchDescriptor<Visit>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        let visits = try modelContext.fetch(descriptor)
        return Self.makeVisitsCSV(from: visits, dateString: Self.currentDateString())
    }

    /// Async export that runs the SwiftData fetch + CSV string-building on a
    /// background context so a large catalog does not freeze the Settings UI.
    func exportClientsToCSVAsync(container: ModelContainer) async throws -> ExportDocument {
        let dateString = Self.currentDateString()
        return try await Task.detached(priority: .userInitiated) {
            let bg = ModelContext(container)
            let descriptor = FetchDescriptor<Client>(sortBy: [SortDescriptor(\.lastName), SortDescriptor(\.firstName)])
            let clients = try bg.fetch(descriptor)
            return Self.makeClientsCSV(from: clients, dateString: dateString)
        }.value
    }

    func exportVisitsToCSVAsync(container: ModelContainer) async throws -> ExportDocument {
        let dateString = Self.currentDateString()
        return try await Task.detached(priority: .userInitiated) {
            let bg = ModelContext(container)
            let descriptor = FetchDescriptor<Visit>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
            let visits = try bg.fetch(descriptor)
            return Self.makeVisitsCSV(from: visits, dateString: dateString)
        }.value
    }

    // MARK: - Pure builders (no DB access — safe to call from any actor)

    /// Date formatter built fresh per export so we don't reach into the MainActor-
    /// isolated `Formatters.dateOnly` from a background context (Swift 6 issue).
    private static func makeRowDateFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.locale = .current
        f.doesRelativeDateFormatting = false
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }

    private static func makeClientsCSV(from clients: [Client], dateString: String) -> ExportDocument {
        let rowFormatter = makeRowDateFormatter()
        var csv = "First Name,Last Name,Phone,Email,Address,Notes,Last Visit\n"
        for client in clients {
            let lastVisit = client.lastVisitDate != nil ? rowFormatter.string(from: client.lastVisitDate!) : ""
            let columns: [String] = [
                client.firstName,
                client.lastName,
                client.phone ?? "",
                client.email ?? "",
                client.address ?? "",
                client.notes ?? "",
                lastVisit
            ]
            csv += columns.map { $0.csvEscaped }.joined(separator: ",") + "\n"
        }
        return ExportDocument(csvData: csv, filename: "Pawtrackr_Clients_\(dateString).csv")
    }

    private static func makeVisitsCSV(from visits: [Visit], dateString: String) -> ExportDocument {
        let rowFormatter = makeRowDateFormatter()
        // Decimal-aware formatter so we don't round-trip through Double and lose
        // precision on large totals.
        let totalFormatter = NumberFormatter()
        totalFormatter.numberStyle = .decimal
        totalFormatter.minimumFractionDigits = 2
        totalFormatter.maximumFractionDigits = 2
        totalFormatter.usesGroupingSeparator = false
        totalFormatter.locale = Locale(identifier: "en_US_POSIX")

        var csv = "Date,Pet,Client,Total,Payment Method,Status,Notes\n"
        for visit in visits {
            let date = rowFormatter.string(from: visit.startedAt)
            let petName = visit.pet?.name ?? "Unknown"
            let clientName = visit.pet?.owner?.fullName ?? "Unknown"
            let total = totalFormatter.string(from: visit.total as NSDecimalNumber) ?? "0.00"
            let payment = visit.payment?.method.displayName ?? "Pending"
            let status = visit.isCompleted ? "Completed" : "Active"
            let notes = visit.note ?? ""
            let columns: [String] = [date, petName, clientName, total, payment, status, notes]
            csv += columns.map { $0.csvEscaped }.joined(separator: ",") + "\n"
        }
        return ExportDocument(csvData: csv, filename: "Pawtrackr_Visits_\(dateString).csv")
    }

    private static func currentDateString() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }
}
