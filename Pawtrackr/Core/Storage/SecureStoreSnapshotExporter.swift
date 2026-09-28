//
//  SecureStoreSnapshotExporter.swift
//  Pawtrackr
//
//  Same-device encrypted backup package for SwiftData store families.
//

import Foundation
import CryptoKit
import OSLog

actor SecureStoreSnapshotExporter {
    enum SnapshotError: LocalizedError {
        case storeNotFound
        case keyUnavailable
        case invalidPackage
        case compressionFailed
        case decryptionFailed

        var errorDescription: String? {
            switch self {
            case .storeNotFound: return "No Pawtrackr store files were found to back up."
            case .keyUnavailable: return "The encrypted backup key is unavailable in Keychain."
            case .invalidPackage: return "This backup package is invalid or incomplete."
            case .compressionFailed: return "The backup could not be compressed."
            case .decryptionFailed: return "The backup could not be decrypted on this device."
            }
        }
    }

    struct SecureSnapshotManifest: Codable, Equatable, Sendable {
        struct Entry: Codable, Equatable, Sendable {
            let relativePath: String
            let byteCount: Int
            let sha256: String
        }

        let id: UUID
        let createdAt: Date
        let appVersion: String
        let appBuild: String
        let schema: String
        let deviceID: UUID
        let storeName: String
        let entries: [Entry]
        let compressedByteCount: Int
        let encryptedByteCount: Int
    }

    static let shared = SecureStoreSnapshotExporter()
    nonisolated static let lastSuccessfulSnapshotDateKey = "secureStoreSnapshot.lastSuccessfulSnapshotDate"

    nonisolated static var hasSuccessfulSnapshotOnThisDevice: Bool {
        UserDefaults.standard.object(forKey: lastSuccessfulSnapshotDateKey) as? Date != nil
    }

    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr", category: "SecureSnapshot")
    private let storeName = "Pawtrackr.store"
    private let keychainKey = "secure-store-snapshot-key-v1"
    private let packageExtension = "pawtrackrbackup"

    @discardableResult
    func exportSnapshot(
        appSupportURL overrideAppSupportURL: URL? = nil,
        destinationDirectory: URL? = nil,
        fileManager: FileManager = .default,
        now: Date = Date()
    ) throws -> URL {
        let appSupportURL = try overrideAppSupportURL ?? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        return try StoreFileLockCoordinator.withStoreLock(in: appSupportURL, reason: "secure snapshot export", fileManager: fileManager) {
            let storeSet = try SQLiteStoreFileSet(baseName: storeName, directory: appSupportURL, fileManager: fileManager)
            guard !storeSet.files.isEmpty else { throw SnapshotError.storeNotFound }
            guard SQLiteStoreFileSet.quickCheck(storeURL: storeSet.primaryStoreURL, fileManager: fileManager) else {
                throw SnapshotError.invalidPackage
            }

            let entries = try archiveEntries(for: storeSet, fileManager: fileManager)
            let archive = try encodeArchive(entries)
            guard let compressed = try (archive as NSData).compressed(using: .lzfse) as Data? else {
                throw SnapshotError.compressionFailed
            }

            let key = try encryptionKey()
            let sealed = try AES.GCM.seal(compressed, using: key)
            guard let encrypted = sealed.combined else { throw SnapshotError.keyUnavailable }

            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
            let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
            let manifest = SecureSnapshotManifest(
                id: UUID(),
                createdAt: now,
                appVersion: version,
                appBuild: build,
                schema: "secure-store-snapshot-v1",
                deviceID: DeviceIdentity.currentID,
                storeName: storeName,
                entries: entries.map {
                    SecureSnapshotManifest.Entry(relativePath: $0.relativePath, byteCount: $0.data.count, sha256: $0.sha256)
                },
                compressedByteCount: compressed.count,
                encryptedByteCount: encrypted.count
            )

            let destinationRoot = try destinationDirectory ?? defaultBackupDirectory(fileManager: fileManager)
            try fileManager.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
            let stamp = ISO8601DateFormatter().string(from: now).replacingOccurrences(of: ":", with: "-")
            let packageURL = destinationRoot.appendingPathComponent("Pawtrackr-\(stamp).\(packageExtension)", isDirectory: true)
            if fileManager.fileExists(atPath: packageURL.path) {
                try fileManager.removeItem(at: packageURL)
            }
            try fileManager.createDirectory(at: packageURL, withIntermediateDirectories: true)
            try JSONEncoder.secureSnapshot.encode(manifest).write(to: packageURL.appendingPathComponent("manifest.json"), options: [.atomic])
            try encrypted.write(to: packageURL.appendingPathComponent("store.archive.aesgcm"), options: [.atomic])

            UserDefaults.standard.set(now, forKey: Self.lastSuccessfulSnapshotDateKey)
            log.info("Created encrypted store snapshot with \(manifest.entries.count, privacy: .public) file(s).")
            return packageURL
        }
    }

    func validateSnapshot(at packageURL: URL) throws -> SecureSnapshotManifest {
        let manifestURL = packageURL.appendingPathComponent("manifest.json")
        let encryptedURL = packageURL.appendingPathComponent("store.archive.aesgcm")
        guard FileManager.default.fileExists(atPath: manifestURL.path),
              FileManager.default.fileExists(atPath: encryptedURL.path)
        else {
            throw SnapshotError.invalidPackage
        }
        let manifest = try JSONDecoder.secureSnapshot.decode(
            SecureSnapshotManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        _ = try decryptArchive(at: packageURL, manifest: manifest)
        return manifest
    }

    private struct ArchiveEntry {
        let relativePath: String
        let data: Data
        let sha256: String
    }

    private func archiveEntries(for storeSet: SQLiteStoreFileSet, fileManager: FileManager) throws -> [ArchiveEntry] {
        var entries: [ArchiveEntry] = []
        for file in storeSet.files {
            let data = try Data(contentsOf: file)
            entries.append(ArchiveEntry(relativePath: file.lastPathComponent, data: data, sha256: data.sha256Hex))
        }

        if let supportDirectory = storeSet.supportDirectory,
           let enumerator = fileManager.enumerator(at: supportDirectory, includingPropertiesForKeys: [.isDirectoryKey]) {
            let rootPath = supportDirectory.standardizedFileURL.path
            for case let url as URL in enumerator {
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
                guard values?.isDirectory != true else { continue }
                let relative = String(url.standardizedFileURL.path.dropFirst(rootPath.count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let packagePath = supportDirectory.lastPathComponent + "/" + relative
                let data = try Data(contentsOf: url)
                entries.append(ArchiveEntry(relativePath: packagePath, data: data, sha256: data.sha256Hex))
            }
        }
        return entries.sorted { $0.relativePath < $1.relativePath }
    }

    private func encodeArchive(_ entries: [ArchiveEntry]) throws -> Data {
        var data = Data()
        data.append("PawtrackrSecureArchiveV1\n".data(using: .utf8)!)
        var count = UInt32(entries.count).bigEndian
        data.append(Data(bytes: &count, count: MemoryLayout<UInt32>.size))
        for entry in entries {
            let name = Data(entry.relativePath.utf8)
            var nameLength = UInt32(name.count).bigEndian
            var byteCount = UInt64(entry.data.count).bigEndian
            data.append(Data(bytes: &nameLength, count: MemoryLayout<UInt32>.size))
            data.append(name)
            data.append(Data(bytes: &byteCount, count: MemoryLayout<UInt64>.size))
            data.append(entry.data)
        }
        return data
    }

    private func decryptArchive(at packageURL: URL, manifest: SecureSnapshotManifest) throws -> Data {
        let encrypted = try Data(contentsOf: packageURL.appendingPathComponent("store.archive.aesgcm"))
        let key = try encryptionKey()
        let sealed = try AES.GCM.SealedBox(combined: encrypted)
        let compressed = try AES.GCM.open(sealed, using: key)
        guard let archive = try (compressed as NSData).decompressed(using: .lzfse) as Data? else {
            throw SnapshotError.decryptionFailed
        }
        let expected = Set(manifest.entries.map(\.relativePath))
        let decoded = try decodeArchiveNames(archive)
        guard Set(decoded) == expected else { throw SnapshotError.invalidPackage }
        return archive
    }

    private func decodeArchiveNames(_ data: Data) throws -> [String] {
        let magic = "PawtrackrSecureArchiveV1\n".data(using: .utf8)!
        guard data.starts(with: magic) else { throw SnapshotError.invalidPackage }
        var cursor = magic.count

        func read<T: FixedWidthInteger>(_ type: T.Type) throws -> T {
            let size = MemoryLayout<T>.size
            guard cursor + size <= data.count else { throw SnapshotError.invalidPackage }
            let value = data[cursor..<cursor + size].withUnsafeBytes { $0.load(as: T.self) }
            cursor += size
            return T(bigEndian: value)
        }

        let count = try Int(read(UInt32.self))
        var names: [String] = []
        names.reserveCapacity(count)
        for _ in 0..<count {
            let nameLength = try Int(read(UInt32.self))
            guard cursor + nameLength <= data.count else { throw SnapshotError.invalidPackage }
            let nameData = data[cursor..<cursor + nameLength]
            cursor += nameLength
            let byteCount = try Int(read(UInt64.self))
            guard cursor + byteCount <= data.count,
                  let name = String(data: nameData, encoding: .utf8)
            else {
                throw SnapshotError.invalidPackage
            }
            cursor += byteCount
            names.append(name)
        }
        return names
    }

    private func encryptionKey() throws -> SymmetricKey {
        if let data = KeychainStorage.data(forKey: keychainKey), data.count == 32 {
            return SymmetricKey(data: data)
        }

        let data = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        guard KeychainStorage.set(data, forKey: keychainKey) else {
            throw SnapshotError.keyUnavailable
        }
        return SymmetricKey(data: data)
    }

    private func defaultBackupDirectory(fileManager: FileManager) throws -> URL {
        let appSupportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupportURL.appendingPathComponent("EncryptedBackups", isDirectory: true)
    }
}

private extension Data {
    var sha256Hex: String {
        SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined()
    }
}

private extension JSONEncoder {
    static var secureSnapshot: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var secureSnapshot: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
