//
//  CheckoutDraftStore.swift
//  Pawtrackr
//

import Foundation
import OSLog

actor CheckoutDraftStore {
    static let shared = CheckoutDraftStore()

    private let directoryURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(directoryURL: URL? = nil) {
        self.directoryURL = directoryURL ?? Self.defaultDirectoryURL()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadDraft(for visitID: UUID) async -> CheckoutDraft? {
        let url = draftURL(for: visitID)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(CheckoutDraft.self, from: data)
        } catch {
            Logger.checkoutDraft.error("Failed to load draft for \(visitID.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func saveDraft(_ draft: CheckoutDraft) async throws {
        try ensureDirectory()
        let url = draftURL(for: draft.visitID)
        let data = try encoder.encode(draft)
        try data.write(to: url, options: .atomic)
    }

    func deleteDraft(for visitID: UUID) async throws {
        let url = draftURL(for: visitID)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        try FileManager.default.removeItem(at: url)
    }

    private func draftURL(for visitID: UUID) -> URL {
        directoryURL.appendingPathComponent("\(visitID.uuidString).json")
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private static func defaultDirectoryURL() -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        return base
            .appendingPathComponent("Pawtrackr", isDirectory: true)
            .appendingPathComponent("CheckoutDrafts", isDirectory: true)
    }
}

private extension Logger {
    static let checkoutDraft = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "CheckoutDraftStore")
}
