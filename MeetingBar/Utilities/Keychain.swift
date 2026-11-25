//
//  Keychain.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 19.05.2025.
//  Copyright © 2025 Andrii Leitsius. All rights reserved.
//

import Security
import Foundation

enum KeychainQueryFactory {
    static func saveQuery(data: Data, service: String, account: String? = nil) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass              as String: kSecClassGenericPassword,
            kSecAttrService        as String: service,
            kSecValueData          as String: data,
            kSecAttrAccessible     as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        query[kSecAttrAccount as String] = account
        return query
    }

    static func loadQuery(service: String, account: String? = nil) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass               as String: kSecClassGenericPassword,
            kSecAttrService         as String: service,
            kSecReturnData          as String: true,
            kSecMatchLimit          as String: kSecMatchLimitOne
        ]
        query[kSecAttrAccount as String] = account
        return query
    }

    static func deleteQuery(service: String, account: String? = nil) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass        as String: kSecClassGenericPassword,
            kSecAttrService  as String: service
        ]
        query[kSecAttrAccount as String] = account
        return query
    }

    /// Attributes only: the file-based macOS keychain rejects returning data
    /// for more than one item at a time.
    static func listAccountsQuery(service: String) -> [String: Any] {
        [
            kSecClass              as String: kSecClassGenericPassword,
            kSecAttrService        as String: service,
            kSecReturnAttributes   as String: true,
            kSecMatchLimit         as String: kSecMatchLimitAll
        ]
    }
}

enum Keychain {
    // MARK: - Public helpers
    @discardableResult
    static func save(data: Data, for service: String, account: String? = nil) -> Bool {
        delete(for: service, account: account)                   // overwrite if exists

        let query = KeychainQueryFactory.saveQuery(data: data, service: service, account: account)
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func load(for service: String, account: String? = nil) -> Data? {
        let query = KeychainQueryFactory.loadQuery(service: service, account: account)
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else {
            return nil
        }
        return item as? Data
    }

    @discardableResult
    static func delete(for service: String, account: String? = nil) -> Bool {
        let query = KeychainQueryFactory.deleteQuery(service: service, account: account)
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }

    static func accounts(for service: String) -> [String] {
        let query = KeychainQueryFactory.listAccountsQuery(service: service)
        var items: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &items) == errSecSuccess,
              let attributes = items as? [[String: Any]] else {
            return []
        }
        return attributes.compactMap { $0[kSecAttrAccount as String] as? String }
    }
}
