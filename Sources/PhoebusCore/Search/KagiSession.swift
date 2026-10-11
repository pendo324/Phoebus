import Foundation
#if canImport(Security)
import Security
#endif

extension Notification.Name {
    /// The saved Kagi Session Link was set or removed (Reborn #1305).
    public static let kagiSessionLinkChanged = Notification.Name("Phoebus.kagiSessionLinkChanged")
}

/// The Session Link behind the Search tab's Kagi mode (Reborn "Kagi Search",
/// #1305): the token from kagi.com → Settings → Account → Session Link. It
/// signs in as the subscriber, so it lives only in the Keychain: never in
/// defaults, never in a log. Backups carry it with the accounts.
public enum KagiSession {
    /// Phoebus's own Keychain identity for the token. Reborn's is
    /// `rebornKeychainService` with the same account.
    public static let keychainService = "com.pendo324.Phoebus.kagi"
    public static let rebornKeychainService = "com.christianselig.Apollo.kagi"
    public static let keychainAccount = "sessionToken"

    #if canImport(Security)
    private static let item = KeychainItem(service: keychainService, account: keychainAccount)

    /// The saved token, nil when none is saved.
    public static var token: String? {
        guard let data = item.read().data, let token = String(data: data, encoding: .utf8), !token.isEmpty else { return nil }
        return token
    }

    private static func store(_ token: String?) -> Bool {
        guard let token, !token.isEmpty else {
            item.delete()
            return true
        }
        return item.write(Data(token.utf8)) == errSecSuccess
    }
    #else
    private final class Memory: @unchecked Sendable {
        private let lock = NSLock()
        private var value: String?
        var token: String? {
            get { lock.lock(); defer { lock.unlock() }; return value }
            set { lock.lock(); defer { lock.unlock() }; value = newValue }
        }
    }
    private static let memory = Memory()

    public static var token: String? { memory.token }

    private static func store(_ token: String?) -> Bool {
        memory.token = token?.isEmpty == false ? token : nil
        return true
    }
    #endif

    public static var hasToken: Bool { token != nil }

    /// Saves `token` (already normalized, see `KagiSearch.normalizeSessionToken`),
    /// or removes the saved one when nil or empty. False when the Keychain
    /// refused the write.
    @discardableResult
    public static func setToken(_ token: String?) -> Bool {
        guard store(token) else { return false }
        if Thread.isMainThread {
            NotificationCenter.default.post(name: .kagiSessionLinkChanged, object: nil)
        } else {
            DispatchQueue.main.async { NotificationCenter.default.post(name: .kagiSessionLinkChanged, object: nil) }
        }
        return true
    }
}
