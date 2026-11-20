// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import Security

enum DeepSeekKeychain {
    enum Issue: LocalizedError, Equatable {
        case invalidKey, missingKey, keychain

        var errorDescription: String? {
            switch self {
            case .invalidKey: String(localized: "Enter a valid DeepSeek API key.")
            case .missingKey: String(localized: "Add a DeepSeek API key in Leaf Settings.")
            case .keychain: String(localized: "Leaf could not access the macOS Keychain.")
            }
        }
    }

    private static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "ai.alano.Leaf") + ".DeepSeek",
            kSecAttrAccount as String: "api-key",
        ]
    }

    static func hasKey() throws -> Bool {
        switch SecItemCopyMatching(query as CFDictionary, nil) {
        case errSecSuccess: return true
        case errSecItemNotFound: return false
        default: throw Issue.keychain
        }
    }

    static func read() throws -> String {
        var request = query
        request[kSecReturnData as String] = true
        var item: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &item)
        if status == errSecItemNotFound { throw Issue.missingKey }
        guard status == errSecSuccess, let data = item as? Data, let key = String(data: data, encoding: .utf8) else {
            throw Issue.keychain
        }
        return key
    }

    static func validatedKey(_ input: String) throws -> String {
        let key = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key.utf8.count <= 512, key.utf8.allSatisfy({ (0x21...0x7e).contains($0) }) else {
            throw Issue.invalidKey
        }
        return key
    }

    static func save(_ input: String) throws {
        let key = try validatedKey(input)
        let change = [kSecValueData as String: Data(key.utf8)]
        let status = SecItemUpdate(query as CFDictionary, change as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw Issue.keychain }
        let item = query.merging(change) { _, new in new }
        let added = SecItemAdd(item as CFDictionary, nil)
        if added == errSecDuplicateItem,
           SecItemUpdate(query as CFDictionary, change as CFDictionary) == errSecSuccess { return }
        guard added == errSecSuccess else { throw Issue.keychain }
    }

    static func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Issue.keychain }
    }
}
