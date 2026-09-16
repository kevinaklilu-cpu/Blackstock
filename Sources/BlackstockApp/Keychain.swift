#if os(macOS)
import Foundation
import Security
struct Keychain {
    static let service = "de.blackstock.native"
    static func read(_ account: String) -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else { return "" }
        return value
    }
    static func write(_ value: String, account: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary); guard !value.isEmpty else { return }; var item = base; item[kSecValueData as String] = Data(value.utf8); SecItemAdd(item as CFDictionary, nil)
    }
}
#endif
