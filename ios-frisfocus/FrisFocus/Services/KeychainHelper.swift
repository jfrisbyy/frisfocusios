//
//  KeychainHelper.swift
//  FrisFocus
//
//  Minimal Keychain wrapper for the Rork Auth access / refresh tokens.
//
//  Every method is `nonisolated` so it can be called both from the
//  @MainActor `AuthManager` and from the Supabase client's `@Sendable`
//  accessToken closure (which runs off the main actor). The Security
//  framework calls are thread-safe, so this is safe.
//

import Foundation
import Security

enum KeychainHelper {
    nonisolated static func set(_ key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]

        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    nonisolated static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    nonisolated static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
