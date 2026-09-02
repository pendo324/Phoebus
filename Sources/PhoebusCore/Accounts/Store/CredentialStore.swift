import Foundation
#if canImport(Security)
import Security
#endif

/// Keychain-backed persistence for the Reddit OAuth credential, so the
/// user doesn't have to re-authenticate every launch. Falls back to an
/// in-memory no-op store on platforms without Security.framework (keeps
/// this buildable and testable on Linux).
public protocol CredentialStore: Sendable {
    func save(_ credential: RedditCredential) throws
    func load() -> RedditCredential?
    func clear()
}

#if canImport(Security)
public struct KeychainCredentialStore: CredentialStore {
    private let item = KeychainItem(service: "com.pendo324.Phoebus.reddit-credential", account: "default")

    public init() {}

    public func save(_ credential: RedditCredential) throws {
        let status = item.write(try JSONEncoder().encode(credential))
        guard status == errSecSuccess else {
            throw CredentialStoreError.keychainError(status)
        }
    }

    public func load() -> RedditCredential? {
        item.read().data.flatMap { try? JSONDecoder().decode(RedditCredential.self, from: $0) }
    }

    public func clear() { item.delete() }
}

public enum CredentialStoreError: Error {
    case keychainError(OSStatus)
}
#else
/// Non-Darwin fallback (e.g. running unit tests on Linux) — no
/// persistence, matches CredentialStore contract for compilation only.
public final class InMemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private var stored: RedditCredential?
    public init() {}
    public func save(_ credential: RedditCredential) throws { stored = credential }
    public func load() -> RedditCredential? { stored }
    public func clear() { stored = nil }
}
#endif
