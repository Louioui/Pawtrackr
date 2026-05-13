//
//  CheckoutEventRecorder.swift
//  Pawtrackr
//

import Foundation
import OSLog

actor CheckoutEventRecorder {
    static let shared = CheckoutEventRecorder()

    private let logURL: URL
    private let maxLines = 300
    private let iso8601 = ISO8601DateFormatter()

    // Buffered lines waiting to be flushed to disk.
    private var pendingLines: [String] = []
    private var flushTask: Task<Void, Never>?

    init(logURL: URL? = nil) {
        self.logURL = logURL ?? Self.defaultLogURL()
    }

    func record(_ event: String, visitID: UUID, petName: String) {
        let line = "\(iso8601.string(from: .now)) | visit=\(visitID.uuidString) | pet=\(petName) | \(event)"
        // OSLog goes to system-wide captures (sysdiagnose, support bundles) where pet
        // name counts as customer PII. Keep the visit UUID public for cross-referencing
        // and redact the rest. The on-disk file log (below) keeps full detail for the
        // user to share intentionally.
        Logger.checkoutTrace.info("checkout event=\(event, privacy: .public) visit=\(visitID.uuidString, privacy: .public) pet=\(petName, privacy: .private(mask: .hash))")

        pendingLines.append(line)

        // Flush immediately once the buffer is large enough; otherwise schedule a deferred flush.
        if pendingLines.count >= 10 {
            flush()
        } else {
            scheduleFlush()
        }
    }

    private func scheduleFlush() {
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(3))
            } catch {
                return
            }
            await self?.flush()
        }
    }

    private func flush() {
        guard !pendingLines.isEmpty else { return }
        flushTask?.cancel()
        flushTask = nil

        let batch = pendingLines
        pendingLines = []

        do {
            try ensureParentDirectory()
            let existing = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
            var lines = existing.split(separator: "\n").map(String.init)
            lines.append(contentsOf: batch)
            if lines.count > maxLines {
                lines = Array(lines.suffix(maxLines))
            }
            try lines.joined(separator: "\n").write(to: logURL, atomically: true, encoding: .utf8)
        } catch {
            Logger.checkoutTrace.error("Failed to persist checkout trace: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func ensureParentDirectory() throws {
        let parent = logURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    }

    private static func defaultLogURL() -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        return base
            .appendingPathComponent("Pawtrackr", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("checkout-events.log")
    }
}

private extension Logger {
    static let checkoutTrace = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "CheckoutTrace")
}
