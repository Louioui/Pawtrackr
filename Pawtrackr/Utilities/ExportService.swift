import Foundation
import SwiftData
import UniformTypeIdentifiers
import CoreTransferable

struct ExportDocument: Transferable {
    let csvData: String
    let filename: String
    
    static var transferRepresentation: some TransferRepresentation {
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

@MainActor
class ExportService {
    static let shared = ExportService()
    
    func exportClientsToCSV(modelContext: ModelContext) throws -> ExportDocument {
        let descriptor = FetchDescriptor<Client>(sortBy: [SortDescriptor(\.lastName), SortDescriptor(\.firstName)])
        let clients = try modelContext.fetch(descriptor)
        
        var csv = "First Name,Last Name,Phone,Email,Address,Notes,Last Visit\n"
        
        for client in clients {
            let lastVisit = client.lastVisitDate != nil ? Formatters.dateOnly.string(from: client.lastVisitDate!) : ""
            
            let columns: [String] = [
                client.firstName,
                client.lastName,
                client.phone ?? "",
                client.email ?? "",
                client.address ?? "",
                client.notes ?? "",
                lastVisit
            ]
            
            let row = columns.map { $0.csvEscaped }.joined(separator: ",")
            csv += row + "\n"
        }
        
        return ExportDocument(csvData: csv, filename: "Pawtrackr_Clients_\(currentDateString()).csv")
    }
    
    func exportVisitsToCSV(modelContext: ModelContext) throws -> ExportDocument {
        let descriptor = FetchDescriptor<Visit>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        let visits = try modelContext.fetch(descriptor)
        
        var csv = "Date,Pet,Client,Total,Payment Method,Status,Notes\n"
        
        for visit in visits {
            let date = Formatters.dateOnly.string(from: visit.startedAt)
            let petName = visit.pet?.name ?? "Unknown"
            let clientName = visit.pet?.owner?.fullName ?? "Unknown"
            // Use a fixed format for numbers in CSV to avoid locale issues (commas as decimal separators)
            let total = String(format: "%.2f", (visit.total as NSDecimalNumber).doubleValue)
            let payment = visit.payment?.method.displayName ?? "Pending"
            let status = visit.isCompleted ? "Completed" : "Active"
            let notes = visit.note ?? ""
            
            let columns: [String] = [
                date,
                petName,
                clientName,
                total,
                payment,
                status,
                notes
            ]
            
            let row = columns.map { $0.csvEscaped }.joined(separator: ",")
            csv += row + "\n"
        }
        
        return ExportDocument(csvData: csv, filename: "Pawtrackr_Visits_\(currentDateString()).csv")
    }
    
    private func currentDateString() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }
}
