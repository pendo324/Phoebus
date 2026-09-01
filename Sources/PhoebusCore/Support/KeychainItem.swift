#if canImport(Security)
import Foundation
import Security

/// One generic-password Keychain item, shared by the credential stores.
///
/// Written in place (`SecItemUpdate`, falling back to add) rather than
/// delete-then-add, which would leave no item if the add failed. Items are
/// readable after the first unlock, so a prewarmed or background launch
/// before the user unlocks still finds its accounts.
struct KeychainItem {
    let service: String
    let account: String

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    @discardableResult
    func write(_ data: Data) -> OSStatus {
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        guard status == errSecItemNotFound else { return status }
        var attributes = query
        attributes.merge(update) { $1 }
        return SecItemAdd(attributes as CFDictionary, nil)
    }

    func read() -> (status: OSStatus, data: Data?) {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        return (status, status == errSecSuccess ? result as? Data : nil)
    }

    func delete() {
        SecItemDelete(query as CFDictionary)
    }
}
#endif
