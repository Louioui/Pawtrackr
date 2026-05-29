//
//  KeychainStorage.swift
//  Pawtrackr
//
//  Minimal Keychain wrapper for short secrets (e.g. the app PIN).
//  Stored with kSecAttrAccessibleWhenUnlockedThisDeviceOnly so the value
//  doesn't sync via iCloud Keychain and isn't accessible until first unlock.
//

import Foundation
import Security
import OSLog

enum KeychainStorage {
    private static let service = (Bundle.main.bundleIdentifier ?? "com.pawtrackr.app") + ".keychain"

    /// Writes (or replaces) a string under `key`.
    @discardableResult
    static func set(_ value: String, forKey key: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        // Try update first; fall back to add.
        let updateAttrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, updateAttrs as CFDictionary)
        if updateStatus == errSecSuccess { return true }

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus != errSecSuccess {
            Logger.security.error("KeychainStorage.set failed for key=\(key, privacy: .public) status=\(addStatus)")
            return false
        }
        return true
    }

    /// Reads a string under `key`, or `nil` if not present / unreadable.
    static func string(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            if status != errSecItemNotFound {
                Logger.security.error("KeychainStorage.string failed for key=\(key, privacy: .public) status=\(status)")
            }
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Removes the value for `key` if present.
    @discardableResult
    static func remove(forKey key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
