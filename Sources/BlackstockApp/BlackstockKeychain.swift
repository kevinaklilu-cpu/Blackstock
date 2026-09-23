#if os(macOS)
import Foundation
import LocalAuthentication
import Security

enum BlackstockKeychain {
    private static let service = "de.blackstock.app"
    private static let interactionLock = NSRecursiveLock()

    // LAContext covers Data Protection keychain items. Existing macOS login
    // keychain ACLs also need the legacy, process-local interaction guard.
    // This changes no keychain permissions or persisted security settings.
    static func withoutUserInteraction<T>(_ operation: () throws -> T) throws -> T {
        interactionLock.lock()
        defer { interactionLock.unlock() }
        var previous: DarwinBoolean = false
        let readStatus = SecKeychainGetUserInteractionAllowed(&previous)
        guard readStatus == errSecSuccess else { throw KeychainError.status(readStatus) }
        let disableStatus = SecKeychainSetUserInteractionAllowed(false)
        guard disableStatus == errSecSuccess else { throw KeychainError.status(disableStatus) }
        defer { SecKeychainSetUserInteractionAllowed(previous.boolValue) }
        return try operation()
    }

    private static func nonInteractiveContext() -> LAContext {
        let context = LAContext()
        context.interactionNotAllowed = true
        return context
    }

    private static func nonInteractiveQuery(
        _ base: [String: Any]
    ) -> [String: Any] {
        var query = base
        query[kSecUseAuthenticationContext as String] =
            nonInteractiveContext()
        return query
    }

    static func read(_ account: String) -> String {
        let query = nonInteractiveQuery([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ])
        var result: CFTypeRef?
        let status = (try? withoutUserInteraction {
            SecItemCopyMatching(query as CFDictionary, &result)
        }) ?? errSecInteractionNotAllowed
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else { return "" }
        return value
    }

    static func write(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let lookup = nonInteractiveQuery([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ])

        let updateStatus = try withoutUserInteraction {
            SecItemUpdate(lookup as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        }
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainError.status(updateStatus)
        }

        let insert = nonInteractiveQuery([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String:
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ])
        let addStatus = try withoutUserInteraction {
            SecItemAdd(insert as CFDictionary, nil)
        }
        guard addStatus == errSecSuccess else {
            throw KeychainError.status(addStatus)
        }
    }


    @discardableResult
    static func deleteAccounts(withPrefix prefix: String) throws -> Int {
        let query = nonInteractiveQuery([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ])
        var result: CFTypeRef?
        let status = try withoutUserInteraction {
            SecItemCopyMatching(query as CFDictionary, &result)
        }
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
        let query = nonInteractiveQuery([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ])
        let status = try withoutUserInteraction {
            SecItemDelete(query as CFDictionary)
        }
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.status(status)
        }
    }

    enum KeychainError: LocalizedError {
        case status(OSStatus)

        var errorDescription: String? {
            switch self {
            case .status(let code) where code == errSecInteractionNotAllowed || code == errSecAuthFailed:
                return "Der Schlüsselbund ist gesperrt oder der Zugriff für diese Blackstock-Version fehlt. Entsperre ihn einmal in macOS und verbinde Google bei Bedarf erneut. Blackstock fordert dein Mac-Passwort nicht wiederholt an."
            case .status(let code):
                return "Schlüsselbund-Zugriff fehlgeschlagen (\(code))."
            }
        }
    }
}
#endif
