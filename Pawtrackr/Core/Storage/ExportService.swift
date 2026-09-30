import Foundation
import SwiftData
import UniformTypeIdentifiers
import CoreTransferable

/// A copy of an export on disk, so the share sheet can hand it over as a
/// named file. AirDrop, Mail and Messages (and Save to Files) take files,
/// not bare data: shared as data only, macOS offered little more than Copy
/// and Books. Copies live in the temporary folder under their own UUID
/// folder, and ones older than an hour are removed when the next is made.
enum SharedExportFile {
    static func write(_ data: Data, named filename: String) throws -> URL {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("SharedExports", isDirectory: true)
        removeStaleCopies(in: root)
        let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(safeName(filename))
        #if os(iOS)
        // Client details: readable only once the device has been unlocked.
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
        return url
    }

    /// A name every file system and receiving app accepts: no slashes or
    /// colons from a pet's or salon's name.
    static func safeName(_ filename: String) -> String {
        let cleaned = filename
            .components(separatedBy: CharacterSet(charactersIn: "/\\:"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Pawtrackr" : cleaned
    }

    private static func removeStaleCopies(in root: URL) {
        let fileManager = FileManager.default
        guard let folders = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-3_600)
        for folder in folders {
            let created = (try? folder.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            if created < cutoff {
                try? fileManager.removeItem(at: folder)
            }
        }
    }
}

public struct ExportDocument: Transferable, Identifiable {
    let csvData: String
    let filename: String

    public var id: String { filename }

    public static var transferRepresentation: some TransferRepresentation {
        // A named file first, for AirDrop, Mail, Messages and Files. The
        // data after it serves Copy and apps that only take data.
        FileRepresentation(exportedContentType: .commaSeparatedText) { doc in
            SentTransferredFile(try SharedExportFile.write(doc.fileData, named: doc.filename))
        }
        DataRepresentation(exportedContentType: .commaSeparatedText) { doc in
            doc.fileData
        }
        .suggestedFileName { doc in doc.filename }
    }

    /// The file as shared: UTF-8 with a byte order mark, which Excel needs
    /// to read accented names ("José", "Muñoz") instead of mangling them.
    var fileData: Data {
        Data([0xEF, 0xBB, 0xBF]) + Data(csvData.utf8)
    }
}

struct ReceiptDocument: Transferable {
    let pdfData: Data
    let filename: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { doc in
            SentTransferredFile(try SharedExportFile.write(doc.pdfData, named: doc.filename))
        }
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
        FileRepresentation(exportedContentType: .pdf) { doc in
            SentTransferredFile(try SharedExportFile.write(doc.pdfData, named: doc.filename))
        }
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

    private static func header(_ key: String, _ value: String) -> String {
        CSVFormat.text(AppLocalization.localized(key, value: value))
    }

    /// One row per client, sorted by last name: contact details, pets, the
    /// emergency contact, and what their visits add up to.
    static func makeClientsCSV(from clients: [Client], dateString: String) -> ExportDocument {
        let dates = CSVDateFormats()
        var rows: [[String]] = [[
            header("export.csv.first_name", "First Name"),
            header("export.csv.last_name", "Last Name"),
            header("export.csv.phone", "Phone"),
            header("export.csv.email", "Email"),
            header("export.csv.address", "Address"),
            header("export.csv.pets", "Pets"),
            header("export.csv.pet_count", "Pet Count"),
            header("export.csv.emergency_contact", "Emergency Contact"),
            header("export.csv.emergency_phone", "Emergency Phone"),
            header("export.csv.visits", "Visits"),
            header("export.csv.lifetime_spend", "Lifetime Spend"),
            header("export.csv.average_visit", "Average Visit"),
            header("export.csv.loyalty_points", "Loyalty Points"),
            header("export.csv.first_visit", "First Visit"),
            header("export.csv.last_visit", "Last Visit"),
            header("export.csv.client_since", "Client Since"),
            header("export.csv.notes", "Notes"),
            header("export.csv.client_id", "Client ID")
        ]]

        for client in clients {
            let pets = (client.pets ?? []).sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            let petList = pets
                .map { "\($0.name) (\($0.species.displayName))" }
                .joined(separator: ", ")
            let visits = pets.flatMap { $0.visits ?? [] }.filter(\.isCompleted)
            let spend = visits.reduce(Decimal.zero) { $0 + $1.total }
            let visitDates = visits.compactMap(\.endedAt)
            // The one the client's profile shows first: by name, then phone.
            let emergency = (client.emergencyContacts ?? []).min { lhs, rhs in
                let byName = lhs.name.localizedStandardCompare(rhs.name)
                if byName == .orderedSame {
                    return lhs.phone.localizedStandardCompare(rhs.phone) == .orderedAscending
                }
                return byName == .orderedAscending
            }
            let emergencyName = emergency.map { contact -> String in
                let relation = contact.relation?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return relation.isEmpty ? contact.name : "\(contact.name) (\(relation))"
            }

            rows.append([
                CSVFormat.text(client.firstName),
                CSVFormat.text(client.lastName),
                CSVFormat.phone(client.phone),
                CSVFormat.text(client.email),
                CSVFormat.text(client.address),
                CSVFormat.text(petList),
                CSVFormat.integer(pets.count),
                CSVFormat.text(emergencyName),
                CSVFormat.phone(emergency?.phone),
                CSVFormat.integer(visits.count),
                CSVFormat.money(spend),
                visits.isEmpty ? "" : CSVFormat.money(spend / Decimal(visits.count)),
                CSVFormat.integer(client.loyaltyPoints),
                dates.day(visitDates.min()),
                dates.day(visitDates.max() ?? client.lastVisitDate),
                dates.day(client.createdAt),
                CSVFormat.text(client.notes),
                client.uuid.uuidString
            ])
        }
        return ExportDocument(csvData: CSVFormat.document(rows), filename: "Pawtrackr_Clients_\(dateString).csv")
    }

    /// One row per visit, newest first: when, who, what was done, and how it
    /// was paid.
    static func makeVisitsCSV(from visits: [Visit], dateString: String) -> ExportDocument {
        let dates = CSVDateFormats()
        let completed = AppLocalization.localized("export.csv.status.completed", value: "Completed")
        let inProgress = AppLocalization.localized("export.csv.status.in_progress", value: "In progress")
        var rows: [[String]] = [[
            header("export.csv.date", "Date"),
            header("export.csv.check_in", "Check-In"),
            header("export.csv.check_out", "Check-Out"),
            header("export.csv.minutes", "Minutes"),
            header("export.csv.client", "Client"),
            header("export.csv.client_phone", "Client Phone"),
            header("export.csv.pet", "Pet"),
            header("export.csv.species", "Species"),
            header("export.csv.breed", "Breed"),
            header("export.csv.services", "Services"),
            header("export.csv.total", "Total"),
            header("export.csv.paid", "Paid"),
            header("export.csv.payment_method", "Payment Method"),
            header("export.csv.payment_reference", "Payment Reference"),
            header("export.csv.status", "Status"),
            header("export.csv.points_earned", "Points Earned"),
            header("export.csv.notes", "Notes"),
            header("export.csv.visit_id", "Visit ID")
        ]]

        for visit in visits {
            let pet = visit.pet
            let owner = pet?.owner
            let services = (visit.items ?? [])
                .sorted { $0.createdAt < $1.createdAt }
                .map { $0.quantity > 1 ? "\($0.name) ×\($0.quantity)" : $0.name }
                .joined(separator: "; ")
            let minutes = visit.duration.map { String(Int(($0 / 60).rounded())) } ?? ""

            rows.append([
                dates.day(visit.startedAt),
                dates.time(visit.startedAt),
                dates.time(visit.endedAt),
                minutes,
                CSVFormat.text(owner?.fullName),
                CSVFormat.phone(owner?.phone),
                CSVFormat.text(pet?.name),
                CSVFormat.text(pet?.species.displayName),
                CSVFormat.text(pet?.breed),
                CSVFormat.text(services),
                visit.isCompleted ? CSVFormat.money(visit.total) : "",
                visit.payment.map { CSVFormat.money($0.amount) } ?? "",
                CSVFormat.text(visit.payment?.method.displayName),
                CSVFormat.text(visit.payment?.externalReference),
                CSVFormat.text(visit.isCompleted ? completed : inProgress),
                visit.loyaltyPointsChange > 0 ? CSVFormat.integer(visit.loyaltyPointsChange) : "",
                CSVFormat.text(visit.note),
                visit.uuid.uuidString
            ])
        }
        return ExportDocument(csvData: CSVFormat.document(rows), filename: "Pawtrackr_Visits_\(dateString).csv")
    }

    private static func currentDateString() -> String {
        CSVDateFormats().day(Date())
    }
}
