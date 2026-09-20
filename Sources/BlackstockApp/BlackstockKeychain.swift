#if os(macOS)
import Foundation
import Security

enum BlackstockKeychain {
    private static let service = "de.blackstock.app"

    static func read(_ account: String) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else { return "" }
        return value
    }

    static func write(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let lookup: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let updateStatus = SecItemUpdate(
            lookup as CFDictionary,
            [
                kSecValueData as String: data
            ] as CFDictionary
        )
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainError.status(updateStatus)
        }

        var insert = lookup
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] =
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(
            insert as CFDictionary,
            nil
        )
        guard addStatus == errSecSuccess else {
            throw KeychainError.status(addStatus)
        }
    }


    @discardableResult
    static func deleteAccounts(withPrefix prefix: String) throws -> Int {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(
            query as CFDictionary,
            &result
        )
        if status == errSecItemNotFound {
            return 0
        }
        guard status == errSecSuccess else {
            throw KeychainError.status(status)
        }

        let items = result as? [[String: Any]] ?? []
        let accounts = items.compactMap {
            $0[kSecAttrAccount as String] as? String
        }
        .filter { $0.hasPrefix(prefix) }

        for account in accounts {
            try delete(account)
        }
        return accounts.count
    }

    static func delete(_ account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.status(status)
        }
    }

    enum KeychainError: Error { case status(OSStatus) }
}
#endif
