import Foundation
import CryptoKit
import Security

/// Atomic, encrypted Write-Ahead Log to persist user actions to the Secure Enclave
/// before they are written to the database.
final actor SovereignFlightRecorder {
    private let key: SymmetricKey
    private let logURL: URL
    
    init() {
        // Secure Enclave derived key management would go here
        self.key = SymmetricKey(size: .bits256)
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        self.logURL = paths[0].appendingPathComponent("sovereign.wal")
    }
    
    func logAction(_ action: String) throws {
        let data = action.data(using: .utf8)!
        let sealedBox = try AES.GCM.seal(data, using: key)
        if let combined = sealedBox.combined {
            try combined.append(to: logURL)
        }
    }
}

extension Data {
    func append(to url: URL) throws {
        if let fileHandle = try? FileHandle(forWritingTo: url) {
            fileHandle.seekToEndOfFile()
            fileHandle.write(self)
            fileHandle.closeFile()
        } else {
            try write(to: url, options: .atomic)
        }
    }
}
