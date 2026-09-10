import Foundation
#if canImport(Security)
import Security
#endif

/// Reborn "Chat drafts" (#1207): an unsent chat message is kept per
/// account and conversation and restored when the conversation reopens.
///
/// As in Reborn, the text lives in the Keychain (it can be sensitive),
/// keyed by an opaque SHA-256 of account + conversation so neither is
/// stored verbatim; saving an empty string removes the draft; a draft
/// expires after 30 days idle; and an empty account or conversation id
/// never reads or writes, so an unresolved identity cannot share a draft.
public enum MessageDraftStore {
    public static let maximumAge: TimeInterval = 30 * 24 * 60 * 60

    /// Where draft records live. The Keychain on Apple platforms; tests
    /// swap in memory.
    public protocol Backend: Sendable {
        func read(_ key: String) -> Data?
        func write(_ data: Data, for key: String)
        func delete(_ key: String)
    }

    nonisolated(unsafe) public static var backend: Backend = defaultBackend()
    nonisolated(unsafe) public static var now: () -> Date = Date.init

    struct Record: Codable {
        let text: String
        let updated: Date
    }

    public static func opaqueKey(account: String, conversation: String) -> String? {
        let account = account.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let conversation = conversation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !account.isEmpty, !conversation.isEmpty else { return nil }
        let material = "apollo-message-draft-v1:\(account.utf8.count):\(account):\(conversation.utf8.count):\(conversation)"
        return SHA256Digest.hex(Data(material.utf8))
    }

    public static func load(account: String, conversation: String) -> String? {
        guard let key = opaqueKey(account: account, conversation: conversation),
              let data = backend.read(key),
              let record = try? JSONDecoder().decode(Record.self, from: data) else { return nil }
        if now().timeIntervalSince(record.updated) > maximumAge {
            backend.delete(key)
            return nil
        }
        return record.text.isEmpty ? nil : record.text
    }

    public static func save(_ text: String, account: String, conversation: String) {
        guard let key = opaqueKey(account: account, conversation: conversation) else { return }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            backend.delete(key)
            return
        }
        guard let data = try? JSONEncoder().encode(Record(text: text, updated: now())) else { return }
        backend.write(data, for: key)
    }

    public static func clear(account: String, conversation: String) {
        save("", account: account, conversation: conversation)
    }

    public final class MemoryBackend: Backend, @unchecked Sendable {
        private var items: [String: Data] = [:]
        private let lock = NSLock()
        public init() {}
        public func read(_ key: String) -> Data? { lock.lock(); defer { lock.unlock() }; return items[key] }
        public func write(_ data: Data, for key: String) { lock.lock(); items[key] = data; lock.unlock() }
        public func delete(_ key: String) { lock.lock(); items[key] = nil; lock.unlock() }
    }

    static func defaultBackend() -> Backend {
        #if canImport(Security) && !os(Linux)
        return KeychainBackend()
        #else
        return MemoryBackend()
        #endif
    }
}

#if canImport(Security) && !os(Linux)
extension MessageDraftStore {
    /// Generic-password items under one service, account = opaque key. A
    /// Keychain failure (e.g. -34018 without entitlements) means the draft is
    /// simply not kept, the safe failure for sensitive text.
    struct KeychainBackend: Backend {
        static let service = "com.pendo324.Phoebus.message-drafts"

        private func query(_ key: String) -> [String: Any] {
            [kSecClass as String: kSecClassGenericPassword,
             kSecAttrService as String: Self.service,
             kSecAttrAccount as String: key]
        }

        func read(_ key: String) -> Data? {
            var q = query(key)
            q[kSecReturnData as String] = true
            q[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess else { return nil }
            return result as? Data
        }

        func write(_ data: Data, for key: String) {
            let q = query(key)
            let update: [String: Any] = [kSecValueData as String: data]
            if SecItemUpdate(q as CFDictionary, update as CFDictionary) == errSecItemNotFound {
                var add = q
                add[kSecValueData as String] = data
                add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                SecItemAdd(add as CFDictionary, nil)
            }
        }

        func delete(_ key: String) {
            SecItemDelete(query(key) as CFDictionary)
        }
    }
}
#endif
