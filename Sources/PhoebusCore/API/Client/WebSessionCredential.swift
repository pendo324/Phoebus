import Foundation
#if canImport(Security)
import Security
#endif

/// Reborn's "Web JSON" OAuth-free login transport: instead of registering
/// a Reddit OAuth app, the user signs in via `reddit.com/login` in an
/// embedded browser, and the app harvests the session cookie plus CSRF
/// "modhash" token, authenticating requests to `www.reddit.com` with
/// `Cookie:` + `X-Modhash:` headers instead of an OAuth bearer. This is the
/// mechanism Reddit's website uses, so it needs no registered API client.
public struct WebSessionCredential: Codable, Sendable, Equatable {
    /// The Reddit username this session authenticates as (from the
    /// `/api/me.json` probe response), lowercased.
    public var username: String
    /// The full serialized `name=value; name2=value2; ...` cookie header
    /// harvested from the WKWebView's cookie store after a successful login
    /// (typically 10-13 cookies: `reddit_session`, `token_v2`, `loid`,
    /// `csrf_token`, `edgebucket`, etc.).
    public var cookieHeader: String
    /// The CSRF "modhash" token, read from `/api/me.json`'s `data.modhash` at
    /// login. Required for write actions (vote/comment/save/submit/subscribe)
    /// via the `X-Modhash` header; a session with a cookie but no modhash is
    /// Reborn's "(read-only: no write token)" state.
    public var modhash: String?
    public var harvestedAt: Date

    public init(username: String, cookieHeader: String, modhash: String?, harvestedAt: Date = Date()) {
        self.username = username.lowercased()
        self.cookieHeader = cookieHeader
        self.modhash = modhash
        self.harvestedAt = harvestedAt
    }

    /// Matches Reborn's "(read-only: no write token)" settings-row condition.
    public var isReadOnly: Bool { modhash == nil || modhash?.isEmpty == true }
}

/// The completeness gate applied before shipping a harvested session.
/// Right after the fetch-based login completes, the jar can briefly lack
/// token_v2 (and /api/me.json can omit the modhash); harvesting that
/// partial state yields a session that works briefly then dies. Lives in
/// PhoebusCore so the rule is testable.
public enum WebSessionCompleteness {
    public static let maxIncompleteHarvestAttempts = 5

    /// A session is only complete with BOTH auth cookies and a write
    /// token. `reddit_session` alone is not enough: Reddit sets it for
    /// anonymous sessions too.
    public static func isComplete(cookieNames: [String], modhash: String?) -> Bool {
        cookieNames.contains("token_v2")
            && cookieNames.contains("reddit_session")
            && !(modhash ?? "").isEmpty
    }
}

/// Keychain-backed persistence for the harvested web session, mirroring
/// `CredentialStore`: the cookie alone fully impersonates the signed-in
/// user, the same sensitivity as an OAuth refresh token.
public protocol WebSessionStore: Sendable {
    func save(_ session: WebSessionCredential) throws
    func load() -> WebSessionCredential?
    func clear()
}

#if canImport(Security)
public struct KeychainWebSessionStore: WebSessionStore {
    private let item = KeychainItem(service: "com.pendo324.Phoebus.reddit-web-session", account: "default")

    public init() {}

    public func save(_ session: WebSessionCredential) throws {
        let status = item.write(try JSONEncoder().encode(session))
        guard status == errSecSuccess else {
            throw CredentialStoreError.keychainError(status)
        }
    }

    public func load() -> WebSessionCredential? {
        item.read().data.flatMap { try? JSONDecoder().decode(WebSessionCredential.self, from: $0) }
    }

    public func clear() { item.delete() }
}
#else
public final class InMemoryWebSessionStore: WebSessionStore, @unchecked Sendable {
    private var stored: WebSessionCredential?
    public init() {}
    public func save(_ session: WebSessionCredential) throws { stored = session }
    public func load() -> WebSessionCredential? { stored }
    public func clear() { stored = nil }
}
#endif

extension WebSessionStore where Self == WebSessionStoreBox {
    /// Type-erased default so callers don't need to name a concrete
    /// platform type at every call site, mirroring
    /// `CredentialStore.platformDefault`'s pattern.
    public static var platformDefault: WebSessionStoreBox { WebSessionStoreBox() }
}

/// Type-erasing box so callers can write `.platformDefault` regardless
/// of which concrete store (Keychain vs in-memory fallback) backs it.
public struct WebSessionStoreBox: WebSessionStore {
    private let box: any WebSessionStore
    public init() {
        #if canImport(Security)
        box = KeychainWebSessionStore()
        #else
        box = InMemoryWebSessionStore()
        #endif
    }
    public func save(_ session: WebSessionCredential) throws { try box.save(session) }
    public func load() -> WebSessionCredential? { box.load() }
    public func clear() { box.clear() }
}
